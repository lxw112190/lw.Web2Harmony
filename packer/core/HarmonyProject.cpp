#include "core/HarmonyProject.h"
#include "core/Json.h"
#include "core/Logging.h"
#include "core/ProcessRunner.h"
#include "core/Hash.h"
#include "core/IconGenerator.h"
#include <Windows.h>
#include <objbase.h>
#include <fstream>
#include <algorithm>
#include <map>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace lw::web2harmony {
namespace fs = std::filesystem;
namespace {
std::string Q(const std::string& s) { return "\"" + EscapeJson(s) + "\""; }
bool Inside(const fs::path& child, const fs::path& parent) {
    const auto c = fs::weakly_canonical(child);
    const auto p = fs::weakly_canonical(parent);
    auto ci=c.begin();
    for(auto pi=p.begin(); pi!=p.end(); ++pi,++ci) {
        if(ci==c.end() || _wcsicmp(ci->c_str(), pi->c_str())!=0) return false;
    }
    return true;
}
std::string Render(const std::string& text, const std::map<std::string,std::string>& values) {
    std::string result;
    std::size_t position=0;
    while(position<text.size()) {
        const auto start=text.find("{{",position);
        if(start==std::string::npos) {result+=text.substr(position); break;}
        result+=text.substr(position,start-position);
        const auto end=text.find("}}",start+2);
        if(end==std::string::npos) throw std::runtime_error("Unclosed template token");
        const auto key=text.substr(start+2,end-start-2);
        const auto found=values.find(key);
        if(found==values.end()) throw std::runtime_error("Unknown template token: "+key);
        result+=found->second;
        position=end+2;
    }
    return result;
}
bool Excluded(const fs::path& relative) {
    for(const auto& part:relative) {
        const auto name=part.u8string();
        if(name==".git" || name=="node_modules" || name==".env" || name.rfind(".env.",0)==0 ||
           name=="signing.local.json" || name=="project.json") return true;
    }
    return false;
}
}
std::string ReadUtf8(const fs::path& file) {
    std::ifstream stream(file,std::ios::binary);
    if(!stream) throw std::runtime_error("Cannot read: "+file.u8string());
    std::ostringstream content; content<<stream.rdbuf();
    auto text=content.str();
    if(text.rfind("\xEF\xBB\xBF",0)==0) text.erase(0,3);
    return text;
}
void WriteUtf8(const fs::path& file,const std::string& text) {
    fs::create_directories(file.parent_path());
    std::ofstream stream(file,std::ios::binary|std::ios::trunc);
    stream.write(text.data(),static_cast<std::streamsize>(text.size()));
    if(!stream) throw std::runtime_error("Cannot write: "+file.u8string());
}
HarmonyProject HarmonyProject::Load(const fs::path& file) {
    const auto j=JsonObject::Parse(ReadUtf8(file));
    if(j.OptionalInteger("schemaVersion",1)!=1) throw std::runtime_error("Unsupported project schema");
    HarmonyProject p;
    p.mode=j.OptionalString("mode","local"); p.name=j.RequiredString("name");
    p.bundleName=j.RequiredString("bundleName"); p.versionName=j.OptionalString("versionName","1.0.0");
    const auto version=j.OptionalInteger("versionCode",1);
    if(version<1 || version>2147483647) throw std::runtime_error("versionCode must be 1..2147483647");
    p.versionCode=static_cast<int>(version);
    auto resolve=[&](const std::string& value) {
        return value.empty()?fs::path{}:fs::absolute(file.parent_path()/fs::u8path(value)).lexically_normal();
    };
    p.source=resolve(j.OptionalString("source","")); p.icon=resolve(j.OptionalString("icon",""));
    p.entry=j.OptionalString("entry","index.html"); p.url=j.OptionalString("url","");
    p.allowHttp=j.OptionalBoolean("allowHttp",false); p.fullscreen=j.OptionalBoolean("fullscreen",false);
    p.orientation=j.OptionalString("orientation","auto");
    p.Validate(); return p;
}
void HarmonyProject::Validate() const {
    if(mode!="local" && mode!="remote") throw std::runtime_error("mode must be local or remote");
    if(name.empty() || name.size()>256) throw std::runtime_error("Application name is required (max 256 UTF-8 bytes)");
    if(bundleName.size()>127 || !std::regex_match(bundleName,std::regex("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+")))
        throw std::runtime_error("Invalid HarmonyOS bundleName");
    if(!std::regex_match(versionName,std::regex("[0-9]+\\.[0-9]+\\.[0-9]+")) || versionCode<1)
        throw std::runtime_error("Use a three-part versionName and positive versionCode");
    if(orientation!="auto" && orientation!="portrait" && orientation!="landscape")
        throw std::runtime_error("orientation must be auto, portrait or landscape");
    if(!icon.empty()) IconGenerator::Inspect(icon);
    if(mode=="local") {
        const auto relative=fs::u8path(entry);
        if(source.empty() || !fs::is_directory(source) || relative.empty() || relative.is_absolute() ||
           relative.has_root_name() || entry.find('\\')!=std::string::npos ||
           entry.find(':')!=std::string::npos)
            throw std::runtime_error("Invalid local Web directory or entry");
        for(const auto& part:relative) if(part==".." || part==".") throw std::runtime_error("Entry must stay inside the Web directory");
        if(!Inside(source/relative,source) || !fs::is_regular_file(source/relative) || Excluded(relative))
            throw std::runtime_error("Web entry was not found or is excluded");
    } else {
        if(!std::regex_match(url,std::regex("https?://[^/\\s?#@]+[^\\s]*")) ||
           (!allowHttp && url.rfind("http://",0)==0))
            throw std::runtime_error("Use an HTTPS URL, or explicitly enable HTTP");
    }
}
fs::path ApplicationRoot() {
    wchar_t buffer[32768]{};
    const auto count=GetModuleFileNameW(nullptr,buffer,32768);
    if(!count || count>=32768) throw std::runtime_error("Cannot resolve executable directory");
    const auto directory=fs::path(buffer).parent_path();
    for(const auto& candidate:{directory.parent_path(),directory.parent_path().parent_path(),directory,fs::current_path()}) {
        if(fs::is_regular_file(candidate/"runtime/build-profile.json5") &&
           fs::is_directory(candidate/"packer/templates") && fs::is_regular_file(candidate/"toolchain.lock.json"))
            return candidate;
    }
    throw std::runtime_error("Place runtime, packer/templates and toolchain.lock.json beside bin, or run from the repository");
}
void ExportProject(const HarmonyProject& p,const fs::path& output,const fs::path& root) {
    p.Validate();
    const auto target=fs::absolute(output).lexically_normal();
    if(output.empty() || (fs::exists(target) && !fs::is_empty(target)))
        throw std::runtime_error("Export directory must be empty; existing projects are never overwritten");
    if(p.mode=="local" && (Inside(target,p.source) || Inside(p.source,target)))
        throw std::runtime_error("Export directory must not overlap the Web source directory");
    const auto templates=root/"packer/templates";
    if(!fs::is_directory(templates)) throw std::runtime_error("Runtime template directory is missing");
    const auto runtime=root/"runtime";
    if(!fs::is_regular_file(runtime/"build-profile.json5")) throw std::runtime_error("Base runtime project is missing");
    if(Inside(target,runtime) || Inside(runtime,target))
        throw std::runtime_error("Generated projects must not overwrite or contain the base runtime");
    const auto lock=JsonObject::Parse(ReadUtf8(root/"toolchain.lock.json"));
    std::map<std::string,std::string> values{
        {"APP_NAME",Q(p.name)},{"BUNDLE_NAME",Q(p.bundleName)},{"VERSION_NAME",Q(p.versionName)},
        {"VERSION_CODE",std::to_string(p.versionCode)},{"ALLOW_HTTP",p.allowHttp?"true":"false"},
        {"FULLSCREEN",p.fullscreen?"true":"false"},{"MODE",Q(p.mode)},{"ORIENTATION",Q(p.orientation)},
        {"ABILITY_ORIENTATION",Q(p.orientation=="auto"?"auto_rotation_restricted":p.orientation)},
        {"START_URL",Q(p.mode=="local"?"https://web2harmony.invalid/"+p.entry:p.url)},
        {"MODEL_VERSION",Q(lock.RequiredString("modelVersion"))},
        {"MIN_SDK",Q(lock.RequiredString("compatibleSdkVersion"))},
        {"TARGET_SDK",Q(lock.RequiredString("targetSdkVersion"))}
    };
    fs::create_directories(target);
    WriteUtf8(target/".lw-export-incomplete","Generation has not completed. Remove this directory and export again if interrupted.\n");
    // Copy only source roots, never runtime build caches, local.properties,
    // signing materials or the base project's sample Web assets.
    for(const auto file:{".gitignore","build-profile.json5","oh-package.json5","hvigorfile.ts",
                         "entry/build-profile.json5","entry/oh-package.json5","entry/hvigorfile.ts"}) {
        fs::create_directories((target/file).parent_path());
        fs::copy_file(runtime/file,target/file);
    }
    for(const auto directory:{"AppScope","hvigor","entry/src/main"}) {
        for(fs::recursive_directory_iterator it(runtime/directory),end;it!=end;++it) {
            const auto relative=it->path().lexically_relative(runtime);
            const auto generic=relative.generic_u8string();
            if(generic=="entry/src/main/resources/rawfile" || Excluded(relative)) {
                if(it->is_directory()) it.disable_recursion_pending();
                continue;
            }
            if((GetFileAttributesW(it->path().c_str()) & FILE_ATTRIBUTE_REPARSE_POINT)!=0)
                throw std::runtime_error("Reparse points are not allowed in the base runtime");
            if(it->is_regular_file()) {
                fs::create_directories((target/relative).parent_path());
                fs::copy_file(it->path(),target/relative);
            }
        }
    }
    std::vector<std::pair<std::string,std::string>> assets;
    if(p.mode=="local") {
        for(fs::recursive_directory_iterator it(p.source),end;it!=end;++it) {
            const auto relative=it->path().lexically_relative(p.source);
            if(Excluded(relative)) {if(it->is_directory()) it.disable_recursion_pending(); continue;}
            if((GetFileAttributesW(it->path().c_str()) & FILE_ATTRIBUTE_REPARSE_POINT)!=0)
                throw std::runtime_error("Reparse points are not allowed in Web assets: "+relative.u8string());
            if(!it->is_regular_file()) continue;
            if(!Inside(it->path(),p.source)) throw std::runtime_error("Web asset escaped source directory");
            const auto dest=target/"entry/src/main/resources/rawfile/www"/relative;
            fs::create_directories(dest.parent_path());
            fs::copy_file(it->path(),dest);
            assets.push_back({"/"+relative.generic_u8string(),"www/"+relative.generic_u8string()});
        }
    }
    std::string mappings;
    for(const auto& asset:assets) mappings+="  ["+Q(asset.first)+", "+Q(asset.second)+"],\n";
    values["ASSET_MAP"]=mappings;
    for(const auto& item:fs::recursive_directory_iterator(templates)) {
        if(!item.is_regular_file()) continue;
        auto relative=item.path().lexically_relative(templates);
        if(relative.extension()==".in") relative.replace_extension();
        if(item.path().extension()!=".in") continue;
        WriteUtf8(target/relative,Render(ReadUtf8(item.path()),values));
    }
    const auto appIcon=p.icon.empty()?root/"assets/default-app-icon.png":p.icon;
    IconGenerator::Inspect(appIcon);
    fs::create_directories(target/"AppScope/resources/base/media");
    fs::copy_file(appIcon,target/"AppScope/resources/base/media/app_icon.png",fs::copy_options::overwrite_existing);
    std::ostringstream checksums;
    for(const auto& asset:assets) {
        const auto relative="entry/src/main/resources/rawfile/"+asset.second;
        checksums<<Sha256File(target/fs::u8path(relative))<<"  "<<relative<<"\n";
    }
    WriteUtf8(target/"WEB-SHA256SUMS.txt",checksums.str());
    WriteUtf8(target/"lw-export.json","{\"schemaVersion\":1,\"generatorVersion\":\"" LW_VERSION "\",\"bundleName\":"+Q(p.bundleName)+",\"mode\":"+Q(p.mode)+",\"webFileCount\":"+std::to_string(assets.size())+"}\n");
    fs::remove(target/".lw-export-incomplete");
    PackerLogger().Info("Export complete; bundle="+p.bundleName+"; webFiles="+std::to_string(assets.size()));
}
void BuildHap(const fs::path& project,const fs::path& root,const fs::path& toolchain,
              const fs::path& javaHome,const fs::path& signing) {
    wchar_t systemRoot[32768]{};
    if(!GetEnvironmentVariableW(L"SystemRoot",systemRoot,32768)) throw std::runtime_error("SystemRoot is missing");
    std::vector<std::wstring> args{L"-NoProfile",L"-ExecutionPolicy",L"Bypass",L"-File",
        (root/"tools/build-hap.ps1").wstring(),L"-ProjectDirectory",fs::absolute(project).wstring(),
        L"-ToolchainDirectory",fs::absolute(toolchain).wstring(),L"-JavaHome",fs::absolute(javaHome).wstring()};
    if(!signing.empty()) {args.push_back(L"-SigningConfiguration");args.push_back(fs::absolute(signing).wstring());}
    ProcessRunner::Run(fs::path(systemRoot)/"System32/WindowsPowerShell/v1.0/powershell.exe",args,root);
}
bool LocalToolchainReady(const fs::path& root) {
    const auto tools=root/"toolchain/command-line-tools";
    return fs::is_regular_file(tools/"bin/hvigorw.bat") && fs::is_regular_file(tools/"bin/ohpm.bat") &&
           fs::is_regular_file(tools/"tool/node/node.exe") &&
           fs::is_regular_file(tools/"sdk/default/sdk-pkg.json") &&
           fs::is_regular_file(root/"toolchain/jdk-21/bin/java.exe");
}
fs::path SigningConfigurationFor(const fs::path& root,const std::string& bundleName) {
    // Never interpret unvalidated UI input as a signing-store path.
    if(!std::regex_match(bundleName,std::regex("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+"))) return {};
    const auto config=root/"signing"/fs::u8path(bundleName)/"signing.local.json";
    return fs::is_regular_file(config)?config:fs::path{};
}
fs::path PackageHap(const HarmonyProject& p,const fs::path& outputDirectory,const fs::path& root) {
    p.Validate();
    if(outputDirectory.empty()) throw std::runtime_error("Select a HAP output directory");
    if(!LocalToolchainReady(root)) throw std::runtime_error("Local toolchain is not ready; prepare toolchain/command-line-tools and toolchain/jdk-21 first");
    const auto output=fs::absolute(outputDirectory).lexically_normal();
    if(p.mode=="local" && Inside(output,p.source)) throw std::runtime_error("HAP output must not be inside the Web source");
    if(Inside(output,root/"runtime") || Inside(output,root/"toolchain") || Inside(output,root/".work"))
        throw std::runtime_error("Choose an output directory outside runtime, toolchain and internal work directories");
    const auto signing=SigningConfigurationFor(root,p.bundleName);
    GUID guid{};
    if(FAILED(CoCreateGuid(&guid))) throw std::runtime_error("Cannot allocate a build workspace");
    wchar_t guidText[40]{};
    StringFromGUID2(guid,guidText,40);
    // Hvigor rejects braces in project paths; use the GUID body only.
    std::wstring jobId=guidText;
    jobId.erase(std::remove_if(jobId.begin(),jobId.end(),[](wchar_t c){return c==L'{' || c==L'}' || c==L'-';}),jobId.end());
    jobId.resize(16);
    const auto job=root/".work"/fs::path(std::wstring(L"pack-")+jobId);
    fs::create_directories(root/".work");
    if(!fs::create_directory(job)) throw std::runtime_error("Build workspace already exists; retry packaging");
    const auto project=job/"project";
    PackerLogger().Info("Package started; bundle="+p.bundleName+"; workspace="+job.u8string());
    try {
        ExportProject(p,project,root);
        BuildHap(project,root,root/"toolchain/command-line-tools",root/"toolchain/jdk-21",signing);
        const auto suffix=signing.empty()?"-unsigned.hap":"-signed.hap";
        const auto built=project/"dist"/fs::u8path(p.bundleName+suffix);
        const auto stem=p.bundleName+"-"+p.versionName+(signing.empty()?"-unsigned":"-signed");
        fs::create_directories(output);
        auto artifact=output/fs::u8path(stem+".hap");
        for(unsigned index=2;fs::exists(artifact) || fs::exists(artifact.wstring()+L".sha256") ||
            fs::exists(artifact.wstring()+L".release.json");++index)
            artifact=output/fs::u8path(stem+"-"+std::to_string(index)+".hap");
        // Commit the HAP last. Never overwrite a previous output.
        const auto metadata=artifact.wstring()+L".release.json";
        const auto checksum=artifact.wstring()+L".sha256";
        fs::copy_file(built.wstring()+L".release.json",metadata);
        WriteUtf8(checksum,Sha256File(built)+"  "+artifact.filename().u8string()+"\n");
        fs::copy_file(built,artifact);
        PackerLogger().Info("HAP packaged: "+artifact.u8string());
        std::error_code cleanupError;
        auto cleanupPath=fs::absolute(job).wstring();
        // Hvigor generates deeply nested cache names. Extended Windows paths
        // keep cleanup working even if a cache exceeds MAX_PATH.
        if(cleanupPath.rfind(L"\\\\?\\",0)!=0) cleanupPath=cleanupPath.rfind(L"\\\\",0)==0?
            L"\\\\?\\UNC\\"+cleanupPath.substr(2):L"\\\\?\\"+cleanupPath;
        fs::remove_all(fs::path(cleanupPath),cleanupError);
        if(cleanupError) PackerLogger().Warn("Workspace cleanup failed: "+job.u8string()+"; error="+cleanupError.message());
        return artifact;
    } catch(...) {
        PackerLogger().Error("Packaging failed; diagnostic workspace retained: "+job.u8string());
        throw;
    }
}
}
