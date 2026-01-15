// Copyright 2025 The Zilkworm Authors (modifications)
// Copyright 2025 The Silkworm Authors
// SPDX-License-Identifier: Apache-2.0

#include <filesystem>
#include <fstream>

#include "../state_transition.hpp"

using namespace silkworm::cmd::state_transition;

namespace {
int run_json_test_file(const std::string& file_path) {
    std::ifstream file(file_path);
    const auto input_str = std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
    if (file.fail()) {
        throw std::runtime_error("Failed to read file: " + file_path);
    }
    std::cout << file_path << "\n";
    const auto terminate_on_error = false;
    const auto show_diagnostics = true;
    auto state_transition = StateTransition(input_str, terminate_on_error, show_diagnostics);
    return static_cast<int>(state_transition.run(1, true));
}

int run_unified_bin_file(const std::string file_path) {
    std::ifstream file(file_path, std::ios::binary);
    const auto input_str = std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
    if (file.fail()) {
        throw std::runtime_error("Failed to read file: " + file_path);
    }
    auto state_transition = StateTransition(input_str);
    auto total_gas = state_transition.run_rlp();
    std::cout << "Cumulative Gas Used: " << total_gas << "\n";

    // TODO: Return non-zero on failure.
    return 0;
}
}  // namespace

int main(int argc, const char* argv[]) {
    try {
        if (argc < 2) {
            std::cerr << "Usage: " << argv[0] << " <path_to_unified_rlp_bin>|<test.json>|<test_dir>\n";
            return 1;
        }
        const std::string file_path = argv[1];

        // Handle JSON tests in a directory.
        if (std::filesystem::is_directory(file_path)) {
            for (const auto& entry : std::filesystem::recursive_directory_iterator(file_path)) {
                const auto& path = entry.path();
                if (path.extension() == ".json") {
                    run_json_test_file(path.string());
                }
            }
            return 0;
        }

        // Handle single JSON test file.
        if (file_path.ends_with(".json")) {
            return run_json_test_file(file_path);
        }

        // Assume binary unified RLP file.
        return run_unified_bin_file(file_path);
    } catch (const std::exception& e) {
        // code to handle exceptions of type std::exception and its derived classes
        const auto desc = e.what();
        std::cerr << "Exception: " << desc << std::endl;
        return 3;
    } catch (...) {
        // code to handle any other type of exception
        std::cerr << "An unknown exception occurred" << std::endl;
        return 4;
    }
    return 0;
}
