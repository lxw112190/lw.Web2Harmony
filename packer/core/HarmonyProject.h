#pragma once
#include <filesystem>
#include <string>
namespace lw::web2harmony {
struct HarmonyProject {
    std::string mode = "local";
    std::string name = u8"我的鸿蒙应用";
    std::string bundleName = "com.example.myharmonyapp";
    std::string versionName = "1.0.0";
    int versionCode = 1;
    std::filesystem::path source;
    std::string entry = "index.html";
    std::string url;
    std::filesystem::path icon;
    bool allowHttp = false;
    bool fullscreen = false;
    std::string orientation = "auto";
    static HarmonyProject Load(const std::filesystem::path& file);
    void Validate() const;
};
std::string ReadUtf8(const std::filesystem::path& file);
void WriteUtf8(const std::filesystem::path& file, const std::string& text);
std::filesystem::path ApplicationRoot();
void ExportProject(const HarmonyProject& project, const std::filesystem::path& output,
                   const std::filesystem::path& applicationRoot);
void BuildHap(const std::filesystem::path& project, const std::filesystem::path& applicationRoot,
              const std::filesystem::path& toolchain, const std::filesystem::path& javaHome,
              const std::filesystem::path& signing = {});
}
