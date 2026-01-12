// Copyright 2025 The Zilkworm Authors (modifications)
// Copyright 2025 The Silkworm Authors
// SPDX-License-Identifier: Apache-2.0

#include <filesystem>
#include <fstream>

#include "../state_transition.hpp"

using namespace silkworm::cmd::state_transition;

namespace {
void run_test_file(const std::string& file_path) {
    std::ifstream file(file_path);
    const auto input_str = std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
    if (file.fail()) {
        throw std::runtime_error("Failed to read file: " + file_path);
    }
    std::cout << file_path << "\n";
    const auto terminate_on_error = false;
    const auto show_diagnostics = true;
    auto state_transition = StateTransition(input_str, terminate_on_error, show_diagnostics);
    state_transition.run(1, true);
}

constexpr std::string_view FAILING_TESTS[]{
    "cancun/eip4788_beacon_root/test_beacon_root_contract_deploy.json",
    "cancun/eip6780_selfdestruct/test_recreate_self_destructed_contract_different_txs.json",
};
}  // namespace

int main(int argc, const char* argv[]) {
    try {
        if (argc < 2) {
            std::cerr << "Usage: " << argv[0] << " <path_to_unified_rlp_bin>|<test.json>|<test_dir>\n";
            return 1;
        }
        const std::string file_path = argv[1];

        if (std::filesystem::is_directory(file_path)) {
            for (const auto& entry : std::filesystem::recursive_directory_iterator(file_path)) {
                const auto& path = entry.path();
                if (path.extension() == ".json") {
                    if (std::ranges::any_of(FAILING_TESTS,
                                            [&path](const auto& fail_test) {
                                                return path.string().ends_with(fail_test);
                                            })) {
                        std::cout << path.string() << "\n  IGNORED (known failing test)\n";
                        continue;
                    }
                    run_test_file(path.string());
                }
            }
            return 0;
        } else if (file_path.ends_with(".json")) {
            run_test_file(file_path);
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
