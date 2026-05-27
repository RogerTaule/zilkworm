// Copyright 2026 The Zilkworm Authors
// SPDX-License-Identifier: Apache-2.0
//
// Native host counterpart of prover/guest_zisk/hello.cpp.
//
// The guest reads input via the zkVM's MMIO (zisk_io.h) and writes outputs via
// the public-outputs slot array; here, both are routed through ziskos's
// extern "C" read_input / write_output, which resolve to ziskos's native impl
// (the same mechanism hints-gen primes via set_native_input + init_hints_file).
//
// Keeping this in lockstep with hello.cpp means a single dispatch + execution
// path serves both targets — and `hint_*` calls emitted from the EVM (when
// instrumented in silkworm_dev / evmone) flow through the same ziskos
// symbols, so native runs capture hints without an I/O detour through Rust.

#include "z6m_ffi.h"

#include <zilk_core/core/common/bytes.hpp>
#include <zilk_core/dev/state_transition.hpp>

#include <cstdint>
#include <string_view>

extern "C" {
// ziskos C ABI — see ziskos/entrypoint/src/zisklib/lib/zkvm_io.rs.
void read_input(const uint8_t** buf_ptr, std::size_t* buf_size);
void write_output(const uint8_t* output, std::size_t size);
}

extern "C" void z6m_run() {
    constexpr std::uint64_t Z6M_FAILED = static_cast<std::uint64_t>(-1);

    const std::uint8_t* data = nullptr;
    std::size_t len = 0;
    read_input(&data, &len);

    if (data == nullptr || len < 1) {
        // Empty input is an explicit "no work" signal, not a failure.
        std::uint64_t zero = 0;
        write_output(reinterpret_cast<const std::uint8_t*>(&zero), sizeof(zero));
        return;
    }

    const bool is_test = (data[0] != 0);
    const std::uint8_t* body = data + 1;
    const std::size_t body_len = len - 1;

    std::uint64_t result = Z6M_FAILED;
    try {
        if (is_test) {
            // EEST JSON path — matches hello.cpp's `is_test` branch.
            std::string_view json_str(reinterpret_cast<const char*>(body), body_len);
            auto st = silkworm::cmd::state_transition::StateTransition(
                json_str, /*terminate_on_error=*/false, /*show_diagnostics=*/true);
            result = st.run();
        } else {
            // unifiedBlockAndStateRlp path.
            silkworm::ByteView view{body, body_len};
            auto st = silkworm::cmd::state_transition::StateTransition(view);
            result = st.run_rlp();
        }
    } catch (...) {
        result = Z6M_FAILED;
    }

    write_output(reinterpret_cast<const std::uint8_t*>(&result), sizeof(result));
}
