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
#
# -mtune=size: optimise for fewer-instruction code paths. On a zkVM,
# instruction count = steps; there's no pipeline / branch prediction
# benefit to chase, so picking the smaller of two equivalent sequences
# wins unambiguously.
#
# -funroll-loops, -fipa-pta and the inline `--param=` budget bumps are
# the survivors of a flag sweep against the 5-block reference corpus
# (mainnet 25,145,982..25,146,222). Many other flags from a prior tuning
# pass (-fmerge-all-constants, -fno-jump-tables, -fmodulo-sched,
# -flive-range-shrinkage, -fipa-icf, -fdevirtualize-speculatively, …)
# moved cost by less than ±0.05 % on this base and were dropped. -fno-
# strict-aliasing was a *regression* (+0.05 % cost) because our current
# arena doesn't need the type-pun escape hatch and turning aliasing off
# blocks GCC optimisations that do apply.
#
# Lifted from the optimisation roadmap recorded in
# `backup/full-zisk-port-2026-05-19` (which used a different rv64im
# base) and re-measured one-by-one on rv64imac.
set(_zisk_arch_flags
    "-march=rv64imac_zicsr_zaamo_zalrsc -mabi=lp64 -mcmodel=medany -mtune=size"
    " -funroll-loops"
    " -fipa-pta"
    " --param=max-inline-insns-single=1600"
    " --param=max-inline-insns-auto=533"
    " --param=inline-unit-growth=266"
    " --param=max-inline-recursive-depth=6"
    " --param=max-completely-peeled-insns=400"
    " --param=large-function-growth=280"
    " --param=large-unit-insns=30000"
)
string(JOIN "" _zisk_arch_flags ${_zisk_arch_flags})

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
