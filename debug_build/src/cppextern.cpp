#include <silkworm/dev/state_transition.hpp>
// bn254_add.hpp
#include <cstdint>
#include <array>
#include <string>
#include "include/semihosting.hpp"

/* These magic symbols are provided by the linker.  */
extern void (*__preinit_array_start[])(void);
extern void (*__preinit_array_end[])(void);
extern void (*__init_array_start[])(void);
extern void (*__init_array_end[])(void);
extern void (*__fini_array_start[])(void);
extern void (*__fini_array_end[])(void);

extern "C" uint64_t sample_run_wrapped(bool is_test, std::string jsonStr1)
{

    // Call global constructors because SP1's _start function doesn't.
    for (auto p = __preinit_array_start; p != __preinit_array_end; ++p)
    {
        (*p)();
    }
    for (auto p = __init_array_start; p != __init_array_end; ++p)
    {
        (*p)();
    }

    sys_println("\nZilkworm guest initialized");
    if (is_test){

    }    

    // Initialize a state_transition object with one Shanghai Transaction - within silkworm
    // auto state_transition = silkworm::cmd::state_transition::StateTransition(jsonStr1, false, true);
    auto state_transition = silkworm::cmd::state_transition::StateTransition(jsonStr1);

    // Run the state transition function of silkworm - EVMONE - silkworm_validate_transition and back
    auto res = state_transition.run_rlp();
    std::string msg = "[state_transition] run successful, gas used: " + std::to_string(res);
    sys_println(msg.c_str());
    return res;
}
