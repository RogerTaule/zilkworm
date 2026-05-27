// Copyright 2026 The Zilkworm Authors
// SPDX-License-Identifier: Apache-2.0
//
// Host-side FFI entry. Mirrors prover/guest_zisk/hello.cpp — both wrap
// z6m::run() (defined in z6m_dispatch.hpp) with target-appropriate scaffolding.
// The host adds a try/catch wrapper so the Rust caller gets a single u64
// failure sentinel instead of unwinding into Rust on an exception. The guest
// is built with -fno-exceptions and just aborts on throw, which is the same
// observable outcome.

#include "z6m_ffi.h"
#include "z6m_dispatch.hpp"

#include <cstdint>

extern "C" void z6m_run() {
    constexpr std::uint64_t Z6M_FAILED = static_cast<std::uint64_t>(-1);

    try {
        z6m::run();
    } catch (...) {
        write_output(reinterpret_cast<const std::uint8_t*>(&Z6M_FAILED),
                     sizeof(Z6M_FAILED));
    }
}
