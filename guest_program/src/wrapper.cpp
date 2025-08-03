#include <silkworm/dev/state_transition.hpp>


extern "C" void sample_run_wrapped() {
    //Initialize a state_transition object with one Shanghai Transaction - within silkworm
    auto state_transition = silkworm::cmd::state_transition::StateTransition(false, true);

    //Run the state transition function of silkworm - EVMONE - silkworm_validate_transition and back
    state_transition.run();

    //Return nothing
    return;
}
