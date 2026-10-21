#include "core/HarmonyProject.h"
#include "core/ProcessRunner.h"
#include "core/Logging.h"
#include <iostream>
#include <stdexcept>
using namespace lw::web2harmony;
int wmain(int argc,wchar_t** argv) {
    try {
        if(argc==2 && std::wstring(argv[1])==L"--version") {std::cout<<LW_VERSION<<std::endl;return 0;}
        if(argc==3 && std::wstring(argv[1])==L"validate") {
            HarmonyProject::Load(argv[2]); std::cout<<"Project valid"<<std::endl; return 0;
        }
        if(argc==4 && std::wstring(argv[1])==L"export") {
            ExportProject(HarmonyProject::Load(argv[2]),argv[3],ApplicationRoot());
            std::cout<<"Harmony project exported: "<<WideToUtf8(argv[3])<<std::endl; return 0;
        }
        if(argc==4 && std::wstring(argv[1])==L"pack") {
            const auto artifact=PackageHap(HarmonyProject::Load(argv[2]),argv[3],ApplicationRoot());
            std::cout<<"HAP packaged: "<<artifact.u8string()<<std::endl;return 0;
        }
        if((argc==5 || argc==6) && std::wstring(argv[1])==L"build") {
            BuildHap(argv[2],ApplicationRoot(),argv[3],argv[4],argc==6?std::filesystem::path(argv[5]):std::filesystem::path{});
            return 0;
        }
        std::cout<<"lw.Web2Harmony " LW_VERSION "\n"
          "  pack project.json <hap-output-directory>\n"
          "  validate project.json\n  export project.json <empty-output-directory>\n"
          "  build <exported-project> <command-line-tools> <jdk-home> [signing.local.json]\n";
        return argc==1?0:2;
    } catch(const std::exception& error) {
        PackerLogger().Error(error.what()); std::cerr<<error.what()<<std::endl; return 1;
    }
}
