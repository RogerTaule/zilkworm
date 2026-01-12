// Copyright 2025 The Zilkworm Authors (modifications)
// Copyright 2025 The Silkworm Authors
// SPDX-License-Identifier: Apache-2.0

#include <filesystem>
#include <fstream>

#include "../state_transition.hpp"

using namespace silkworm::cmd::state_transition;

int main(int argc, const char* argv[]) {
    try {
        if (argc < 2) {
            std::cerr << "Usage: " << argv[0] << " <path_to_unified_rlp_bin>|<test.json>|<test_dir>\n";
            return 1;
        }
        const std::string file_path = argv[1];

        if (file_path.ends_with(".json") || std::filesystem::is_directory(file_path)) {
            std::cerr << "JSON\n";
            std::ifstream file(file_path);
            const auto input_str = std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
            if (file.fail()) {
                throw std::runtime_error("Failed to read file: " + file_path);
            }
            const auto terminate_on_error = false;
            const auto show_diagnostics = true;
            auto state_transition = StateTransition(input_str, terminate_on_error, show_diagnostics);
            auto total_gas = state_transition.run(1, true);
            std::cout << "Cumulative Gas Used: " << total_gas << "\n";
            return 0;
        }

        {
            std::ifstream file(file_path, std::ios::binary);
            const auto input_str = std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
            if (file.fail()) {
                throw std::runtime_error("Failed to read file: " + file_path);
            }
            auto state_transition = StateTransition(input_str);
            auto total_gas = state_transition.run_rlp();
            std::cout << "Cumulative Gas Used: " << total_gas << "\n";
            return 0;
        }
        return 0;
    } catch (const std::exception& e) {
        // code to handle exceptions of type std::exception and its derived classes
        const auto desc = e.what();
        std::cerr << "Exception: " << desc << std::endl;
    } catch (...) {
        // code to handle any other type of exception
        std::cerr << "An unknown exception occurred" << std::endl;
    }
    return 0;
}
