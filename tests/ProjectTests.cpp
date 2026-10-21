#include "core/HarmonyProject.h"
#include "core/Json.h"
#include "core/Hash.h"
#include "core/Logging.h"
#include <chrono>
#include <iostream>
#include <stdexcept>
namespace fs=std::filesystem;
using namespace lw::web2harmony;
void Require(bool ok,const char* text){if(!ok)throw std::runtime_error(text);}
template<class F> void Rejected(F f,const char* text){bool rejected=false;try{f();}catch(...){rejected=true;}Require(rejected,text);}
int wmain(int argc,wchar_t** argv) {
    if(argc!=2)return 2;
    const fs::path root=argv[1];
    const auto work=root/"build"/fs::u8path("tests-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    try{
        const auto p=HarmonyProject::Load(root/"samples/hello/project.json");
        ExportProject(p,work/"hello",root);
        const auto target=work/"hello";
        Require(fs::is_regular_file(target/fs::u8path(u8"entry/src/main/resources/rawfile/www/测试页/index.html")),"Unicode asset missing");
        Require(Sha256File(p.source/"index.html")==Sha256File(target/"entry/src/main/resources/rawfile/www/index.html"),"Web asset bytes changed");
        Require(ReadUtf8(target/"entry/src/main/ets/common/WebAssets.ets").find(u8"/测试页/index.html")!=std::string::npos,"Unicode mapping missing");
        Require(ReadUtf8(target/"AppScope/resources/base/element/string.json").find(u8"鸿蒙网页测试")!=std::string::npos,"Unicode application name corrupted");
        Require(!fs::exists(target/".lw-export-incomplete"),"Incomplete marker left after success");
        Rejected([&]{ExportProject(p,target,root);},"Must not overwrite existing project");
        Rejected([&]{ExportProject(p,p.source/"nested",root);},"Must reject recursive output");
        auto invalid=p;invalid.entry="../index.html";Rejected([&]{invalid.Validate();},"Must reject path traversal");
        invalid=p;invalid.bundleName="bad/bundle";Rejected([&]{invalid.Validate();},"Must reject invalid bundle");
        invalid=p;invalid.versionCode=-1;Rejected([&]{invalid.Validate();},"Must reject invalid version");
        invalid=p;invalid.mode="remote";invalid.url="http://example.com";Rejected([&]{invalid.Validate();},"Must reject implicit HTTP");
        auto remote=HarmonyProject::Load(root/"samples/remote/project.json");
        ExportProject(remote,work/"remote",root);
        Require(!fs::exists(work/"remote/entry/src/main/resources/rawfile/www"),"Remote should not bundle Web assets");
        const auto source=work/"custom-web";
        WriteUtf8(source/"index.html","<!doctype html>");
        WriteUtf8(source/".env","TOKEN=must-not-package");
        WriteUtf8(source/"project.json","{}");
        WriteUtf8(source/fs::u8path("空 格/日本語.txt"),u8"用户说明");
        auto custom=p;custom.source=source;custom.name=u8"我的网页应用-3 {{ASSET_MAP}}";
        ExportProject(custom,work/"custom",root);
        Require(!fs::exists(work/"custom/entry/src/main/resources/rawfile/www/.env"),"Secrets file leaked");
        Require(!fs::exists(work/"custom/entry/src/main/resources/rawfile/www/project.json"),"Project config leaked");
        Require(fs::is_regular_file(work/fs::u8path(u8"custom/entry/src/main/resources/rawfile/www/空 格/日本語.txt")),"Space/Japanese asset missing");
        Require(ReadUtf8(work/"custom/entry/src/main/ets/common/AppConfig.ets").find("{{ASSET_MAP}}")!=std::string::npos,"User data was interpreted as a template");
        const auto link=source/"unsafe-link";
        std::error_code symlinkError;fs::create_directory_symlink(root/"assets",link,symlinkError);
        if(!symlinkError)Rejected([&]{ExportProject(custom,work/"symlink-export",root);},"Must reject symlink");
        {auto log=Logger::Rotating("rotation-test",work/"logs/packer.log",{256,2});for(int i=0;i<50;i++)log.Info(u8"中文轮转日志测试 "+std::to_string(i));log.Flush();}
        Require(fs::is_regular_file(work/"logs/packer.1.log"),"Log rotation missing");
        std::cout<<"Project export, Unicode paths, validation, exclusion and rotating log tests passed\n";
        fs::remove_all(work);return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<"\n";std::error_code ignored;fs::remove_all(work,ignored);return 1;}
}
