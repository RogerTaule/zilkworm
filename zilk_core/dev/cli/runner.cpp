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
            std::cerr << "Usage: " << argv[0] << " <path_to_unified_rlp_bin>\n"
                      << "[is_test]";
            return 1;
        }
        const std::string file_path = argv[1];
        std::ifstream file(file_path);
        if (!file.is_open()) {
            throw std::runtime_error("Could not open file: " + file_path);
        }
        auto input_str = std::string((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());

        if (argc == 3 && std::string(argv[2]) == "is_test") {
            auto state_transition = StateTransition(input_str, false, true);
            auto total_gas = state_transition.run(1, true);
            std::cout << "Cumulative Gas Used: " << total_gas << "\n";
        } else {
            auto state_transition = silkworm::cmd::state_transition::StateTransition(std::move(input_str));
            auto total_gas = state_transition.run_rlp();
            printf("Cumulative Gas Used: %lu\n", total_gas);
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
