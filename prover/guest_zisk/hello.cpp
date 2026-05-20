/* hello.cpp — L4 link attempt: invoke silkworm::cmd::state_transition.
 *
 * This is the same entry the hypercube guest uses (StateTransition with
 * a ByteView ctor + run_rlp()), translated to read the input from Zisk's
 * memory-mapped INPUT region. If this links cleanly, we've reached L4
 * at link time — the input will almost certainly NOT be a valid RLP
 * block at this point, so the runtime path will fail or abort, but the
 * link surface tells us what runtime stubs are still missing.
 */
#include "zisk_io.h"
#include <zilk_core/core/common/bytes.hpp>
#include <zilk_core/dev/state_transition.hpp>

int main() {
    zisk_input_t inp = read_input();
    silkworm::ByteView view{inp.ptr, inp.len};

    auto st = silkworm::cmd::state_transition::StateTransition(view);
    uint64_t gas_used = st.run_rlp();

    sys_println("gas_used:");
    sys_print_u64_hex(gas_used);
    uart_putc('\n');

    set_output_u64(0, gas_used);
    return 0;
}
