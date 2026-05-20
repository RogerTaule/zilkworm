// Copyright The Zilkworm Authors
// SPDX-License-Identifier: Apache-2.0
#pragma once
#ifdef SP1
#include <sp1_syscalls.hpp>
#elif defined(QEMU_DEBUG)
#include <semihosting.hpp>
#elif defined(ZISK)
/* Bare-metal Zisk: write straight to the memory-mapped UART
 * (0xA0000200) and halt via the QEMU_EXIT_ADDR convention
 * (write 0x5555 to 0x100000). No iostream / locale machinery,
 * so no __init_array execution required. */
#include <cstdint>
#include <string_view>
namespace zilk_core_zisk_print_detail {
    inline void uart_write(const char* p, std::size_t n) {
        auto* uart = reinterpret_cast<volatile unsigned char*>(0xA0000200);
        for (std::size_t i = 0; i < n; ++i) *uart = static_cast<unsigned char>(p[i]);
    }
    inline std::size_t cstr_len(const char* p) {
        std::size_t n = 0;
        while (p[n]) ++n;
        return n;
    }
}
inline void sys_print(const char* msg) {
    using namespace zilk_core_zisk_print_detail;
    uart_write(msg, cstr_len(msg));
}
inline void sys_println(const char* msg) {
    using namespace zilk_core_zisk_print_detail;
    uart_write(msg, cstr_len(msg));
    char nl = '\n';
    uart_write(&nl, 1);
}
inline void sys_print(std::string_view msg) {
    zilk_core_zisk_print_detail::uart_write(msg.data(), msg.size());
}
inline void sys_println(std::string_view msg) {
    zilk_core_zisk_print_detail::uart_write(msg.data(), msg.size());
    char nl = '\n';
    zilk_core_zisk_print_detail::uart_write(&nl, 1);
}
[[noreturn]] inline void syscall_halt(uint8_t /*exit_code*/) {
    *reinterpret_cast<volatile unsigned int*>(0x100000) = 0x5555;
    for (;;) {}
}
#else
#include <iostream>
#include <string_view>
inline void sys_println(const char* msg) {
    std::cout << "stdout: " << msg << std::endl;
}
inline void sys_print(const char* msg) {
    std::cout << "stdout: " << msg;
}
inline void sys_println(std::string_view msg) {
    std::cout << "stdout: " << msg << std::endl;
}
inline void sys_print(std::string_view msg) {
    std::cout << "stdout: " << msg;
}

[[noreturn]] inline void syscall_halt(uint8_t exit_code) {
    std::exit(exit_code);
}

#endif
