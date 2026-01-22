#include <zilk_core/dev/state_transition.hpp>
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

namespace {
    uint64_t run_json_test(const std::string& json_str) {
        const auto terminate_on_error = false;
        const auto show_diagnostics = true;
        auto state_transition = silkworm::cmd::state_transition::StateTransition(json_str, terminate_on_error, show_diagnostics);
        return state_transition.run(1, true);
    }

    uint64_t run_unified_rlp(const std::string& unified_rlp_str) {
        // TODO
        return 0;
    }
}

extern "C" uint64_t sample_run_wrapped(bool is_test, std::string input_str) {

    // Call global constructors because SP1's _start function doesn't.
    for (auto p = __preinit_array_start; p != __preinit_array_end; ++p) {
        (*p)();
    }
    for (auto p = __init_array_start; p != __init_array_end; ++p) {
        (*p)();
    }

    sys_println("\nZilkworm guest initialized");
    if (is_test) {
        sys_println("\nRunning test input");
        return run_json_test(input_str);
    }
    else {
        return run_unified_rlp(input_str);
    }
}
