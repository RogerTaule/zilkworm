/* hello.cpp — Zisk guest entry for block execution.
 *
 * Reads a single payload from the Zisk INPUT region. The first byte is
 * an `is_test` dispatch flag:
 *   0  → bytes [1..] are a unifiedBlockAndStateRlp blob;
 *        run StateTransition::run_rlp() and emit cumulative gas_used.
 *   !0 → bytes [1..] are an Ethereum/Execution-Spec-Tests JSON file;
 *        run StateTransition::run() (which validates against the
 *        expected post-state inside the JSON) and emit its return code.
 *
 * The framing mirrors prover/guest_hypercube/src/main.cpp so the same
 * test inputs (EEST blockchain_tests/* JSONs, unifiedBlockAndStateRlp
 * .bin captures) work across both backends.
 */
#include "zisk_io.h"
#include <zilk_core/core/common/bytes.hpp>
#include <zilk_core/dev/state_transition.hpp>

#include <string_view>

int main() {
    zisk_input_t inp = read_input();
    if (inp.len < 1) {
        sys_println("input too short (need at least the is_test byte)");
        set_output_u64(0, 0);
        return 0;
    }
    const bool is_test = (inp.ptr[0] != 0);
    const unsigned char *body = inp.ptr + 1;
    const unsigned long  body_len = inp.len - 1;

    uint64_t result = 0;

    if (is_test) {
        std::string_view json_str(reinterpret_cast<const char *>(body), body_len);
        auto st = silkworm::cmd::state_transition::StateTransition(
            json_str, /*terminate_on_error=*/false, /*show_diagnostics=*/true);
        result = st.run();
    } else {
        silkworm::ByteView view{body, body_len};
        auto st = silkworm::cmd::state_transition::StateTransition(view);
        result = st.run_rlp();
    }

    sys_println("gas_used:");
    sys_print_u64_hex(result);
    uart_putc('\n');

    set_output_u64(0, result);
    return 0;
}
