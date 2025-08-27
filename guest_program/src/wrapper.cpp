#include <silkworm/dev/state_transition.hpp>
#include "rust/cxx.h"

extern "C" uint64_t sample_run_wrapped(uint32_t n, rust::Str jsonStr1) {
    //Initialize a state_transition object with one Shanghai Transaction - within silkworm
    auto state_transition = silkworm::cmd::state_transition::StateTransition(jsonStr1.data(), false, true);

    //Run the state transition function of silkworm - EVMONE - silkworm_validate_transition and back
    return state_transition.run(n);
}


// Cycle count
// small json alone - Number of cycles: 628815

// With execution and state transition