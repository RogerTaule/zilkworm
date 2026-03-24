#include <zilk_core/dev/state_transition.hpp>
#include "include/sp1_syscalls.hpp"
#include <cstdint>
#include <format>
#include <string_view>

extern "C" int main()
{
    ReadVecResult bool_buf = read_vec_raw();
    bool is_test = (bool_buf.len > 0 && bool_buf.ptr[0] != 0);

    ReadVecResult input_buf = read_vec_raw();

    sys_println("Zilkworm guest initialized");

    uint64_t result = 0;

    if (is_test)
    {
        std::string_view json_str(reinterpret_cast<const char *>(input_buf.ptr),
                                  input_buf.len);
        auto st = silkworm::cmd::state_transition::StateTransition(
            json_str, false, true);
        result = st.run();
    }
    else
    {
        silkworm::ByteView view(input_buf.ptr, input_buf.len);
        auto st = silkworm::cmd::state_transition::StateTransition(view);
        result = st.run_rlp();
    }

    sys_println(std::format("[state_transition] run successful, gas used: {}", result));

    uint8_t result_bytes[8];
    for (int i = 0; i < 8; i++)
        result_bytes[i] = static_cast<uint8_t>(result >> (i * 8));

    syscall_write(SP1_FD_PUBLIC_VALUES, result_bytes, 8);
    return 0;
}
