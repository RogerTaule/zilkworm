#!/usr/bin/env bash
# Build the minimal Zisk C cross-compile POC.
#
# Requires: riscv-none-elf-gcc in PATH (e.g., xPack toolchain 15.2+).
#           ziskemu in PATH (cargo zisk setup).
#
# Output:   hello.elf — run with `ziskemu -e hello.elf`
#
# See docs/zisk_for_cpp_programs.md for the full how-to.
set -euo pipefail
cd "$(dirname "$0")"

GCC="${GCC:-riscv-none-elf-gcc}"

"$GCC" \
    -march=rv64ima_zicsr -mabi=lp64 -mcmodel=medany \
    -nostartfiles -T zisk.ld -Iinclude \
    hello.c _start.s -o hello.elf

echo "Built: $(pwd)/hello.elf"
echo "Run:   ziskemu -e hello.elf"
