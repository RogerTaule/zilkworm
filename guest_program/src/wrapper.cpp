#include <silkworm/dev/state_transition.hpp>
#include "rust/cxx.h"

// bn254_add.hpp
#include <cstdint>
#include <array>
#include "include/sp1_syscalls.hpp"

extern "C" uint64_t sample_run_wrapped(uint32_t n, rust::Str jsonStr1) {
    //Initialize a state_transition object with one Shanghai Transaction - within silkworm
    auto state_transition = silkworm::cmd::state_transition::StateTransition(jsonStr1.data(), false, true);

    //Run the state transition function of silkworm - EVMONE - silkworm_validate_transition and back
    auto res = state_transition.run(n);
    std::string msg = "[state_transition] run successful, gas used: " + std::to_string(res);
    sys_println(msg.c_str());
    return res;
}

// #include "tests/sp1_syscalls_tests.cpp"

// extern "C" uint64_t sample_run_wrapped(uint32_t n, rust::Str jsonStr1) {
//     run_sp1_basic_smoke_tests();
//     run_sp1_crypto_shape_tests();
//     // return uint32_t(P.at(0));
//     return 0;
// }
