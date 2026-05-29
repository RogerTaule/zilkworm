// Single block runner shared between guest (hello.cpp) and host FFI (ffi.cpp).
//
// Both entries reduce to `z6m::run()`. read_input / write_output / the
// zkvm_* precompile symbols are all resolved from `libziskos_staticlib.a`
// (the `ziskos-staticlib` crate in the zisk repo), built per-target:
//   - host:  picked up via the host binary's Rust deps on ziskos.
//   - guest: linked explicitly in prover/guest_zisk/CMakeLists.txt
//            from the riscv64ima-zisk-zkvm-elf build.
//
// install_zkvm_provider() is idempotent (sets a process-global pointer to
// a static provider) so calling it from run() each invocation is safe for
// multi-block hints-gen and zero-cost in the steady state. The provider
// itself is mandatory in zilkworm — see third_party/CMakeLists.txt — so
// there's no #ifdef guard on the install.

#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>

#include <zilk_core/core/common/bytes.hpp>
#include <zilk_core/dev/state_transition.hpp>

#include <evmone/crypto_provider.hpp>
#include <zkvm_io.h>

namespace z6m {

inline std::uint64_t dispatch(
    const std::uint8_t* body, std::size_t body_len, bool is_test)
{
    if (is_test) {
        std::string_view json_str(reinterpret_cast<const char*>(body), body_len);
        auto st = silkworm::cmd::state_transition::StateTransition(
            json_str, /*terminate_on_error=*/false, /*show_diagnostics=*/true);
        return st.run();
    }
    silkworm::ByteView view{body, body_len};
    auto st = silkworm::cmd::state_transition::StateTransition(view);
    return st.run_rlp();
}

// One block end-to-end: install crypto provider, read input, dispatch on the
// is_test flag, write the u64 result. Callers in -fno-exceptions code (guest)
// can't catch any throw from dispatch — the guest will abort, which has the
// same observable effect as a host Z6M_FAILED return.
inline void run()
{
    // Route evmone precompiles through ziskos's zkvm_* implementations so the
    // program CONSUMES the precompile hints emitted by hints-gen instead of
    // recomputing them natively (slow path in a zk circuit).
    evmone::crypto::install_zkvm_provider();

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

    const std::uint64_t result = dispatch(body, body_len, is_test);
    write_output(reinterpret_cast<const std::uint8_t*>(&result), sizeof(result));
}

}  // namespace z6m
