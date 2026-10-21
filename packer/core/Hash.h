#pragma once

#include <filesystem>
#include <string>

namespace lw::web2harmony {

std::string Sha256File(const std::filesystem::path& file);

}  // namespace lw::web2harmony
