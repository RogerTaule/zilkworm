// Copyright 2025 The Silkworm Authors
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <memory>

#include <evmc/evmc.hpp>
#include <zilk_core/core/common/bytes.hpp>

namespace silkworm::cmd::state_transition {

class StateTransition {
  private:
    std::string_view json_str_;
    ByteView unified_rlp_;
    bool terminate_on_error_{false};
    bool show_diagnostics_{false};

  public:
    explicit StateTransition(std::string_view json_str, bool terminate_on_error, bool show_diagnostics) noexcept;
    explicit StateTransition(const std::string& unified_rlp_str) noexcept;
    explicit StateTransition(ByteView& unified_rlp) noexcept;
    static evmc::address to_evmc_address(const std::string& address);
    std::unique_ptr<evmc::address> sender_to_address(const std::string& sender);
    uint64_t run();
    uint64_t run_rlp();
};

}  // namespace silkworm::cmd::state_transition
