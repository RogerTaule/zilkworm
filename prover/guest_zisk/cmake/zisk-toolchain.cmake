# Toolchain file for cross-compiling C/C++ to the Zisk zkVM target
# (riscv64ima, lp64 ABI, medany code model).
#
# Usage:
#   cmake -B build -S . -DCMAKE_TOOLCHAIN_FILE=cmake/zisk-toolchain.cmake
#
# Override the compiler search by setting ZISK_TOOLCHAIN_PREFIX to the
# directory containing riscv-none-elf-{gcc,g++,...} before invoking cmake,
# e.g. xPack 15.2's bin/.

set(CMAKE_SYSTEM_NAME      Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv64)

# Bare-metal target: no try_run, no link checks against host libs.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

if(DEFINED ENV{ZISK_TOOLCHAIN_PREFIX})
    set(_zisk_prefix "$ENV{ZISK_TOOLCHAIN_PREFIX}/")
else()
    set(_zisk_prefix "")
endif()

set(CMAKE_C_COMPILER   "${_zisk_prefix}riscv-none-elf-gcc")
set(CMAKE_CXX_COMPILER "${_zisk_prefix}riscv-none-elf-g++")
set(CMAKE_ASM_COMPILER "${_zisk_prefix}riscv-none-elf-gcc")
set(CMAKE_OBJCOPY      "${_zisk_prefix}riscv-none-elf-objcopy" CACHE FILEPATH "")
set(CMAKE_OBJDUMP      "${_zisk_prefix}riscv-none-elf-objdump" CACHE FILEPATH "")

# Architecture, ABI and code model — must match the Zisk linker script.
# zicsr is required for `csrr marchid` used in _start.s to dispatch the
# emulator-vs-prover exit path. medany is required because .text lives in
# ROM (0x80000000) and .data in RAM (0xa0030000+), beyond medlow's reach.
set(_zisk_arch_flags "-march=rv64imac_zicsr_zaamo_zalrsc -mabi=lp64 -mcmodel=medany")

set(CMAKE_C_FLAGS_INIT   "${_zisk_arch_flags}")
# Bare-metal guest defensive flags:
#   -fno-exceptions / -fno-rtti           : we don't throw and don't dynamic_cast
#   -fno-asynchronous-unwind-tables       : drops .eh_frame (dead with -fno-exceptions)
#   -fno-unwind-tables                    : drops .eh_frame_hdr too
#   -fno-threadsafe-statics               : single-threaded, no __cxa_guard_* (~58 sites)
set(CMAKE_CXX_FLAGS_INIT "${_zisk_arch_flags} -fno-exceptions -fno-rtti -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-threadsafe-statics")
set(CMAKE_ASM_FLAGS_INIT "${_zisk_arch_flags}")

# Don't look at the host's libc; this target has no system root.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
