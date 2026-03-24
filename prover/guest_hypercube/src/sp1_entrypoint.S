/* SP1 zkVM entry point for rv64im C++ guest.
 *
 * Sets up global pointer, stack pointer, and calls __start
 * which initialises the C++ runtime then calls main().
 */

    .section .text._start
    .globl _start
    .type _start, @function
_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    /* Stack top = 0x78000000 (SP1 convention). */
    li      sp, 0x78000000

    /* Call C++ __start() which initialises the runtime and calls main */
    call    __start

    /* Should never return; __start calls syscall_halt.
       If it does, spin forever. */
1:  j       1b

    .size _start, . - _start
