#pragma once

#include <filesystem>
#include <string>
#include <vector>

namespace lw::web2harmony {

class ProcessRunner {
public:
    static void Run(const std::filesystem::path& executable,
                    const std::vector<std::wstring>& arguments,
                    const std::filesystem::path& workingDirectory = {});
};

std::wstring Utf8ToWide(const std::string& value);
std::string WideToUtf8(const std::wstring& value);

}  // namespace lw::web2harmony
