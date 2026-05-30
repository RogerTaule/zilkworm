.section .text.init,"ax",@progbits
.global _start
.type _start, @function
_start:
    .option push
    .option norelax
    la gp, _global_pointer
    .option pop
    la sp, _init_stack_top

    /* Init the shared bump allocator before C++ static ctors run — they
     * allocate via arena_malloc.cpp which delegates to sys_alloc_aligned. */
    call init_sys_alloc

    /* Run .init_array (C++ static ctors). s0/s1 are callee-saved. */
    la s0, __init_array_start
    la s1, __init_array_end
.Linit_loop:
    beq s0, s1, .Linit_done
    ld t0, 0(s0)
    addi s0, s0, 8
    jalr ra, t0
    j .Linit_loop
.Linit_done:

    call main
    csrr t0, marchid
    li   t1, 0xFFFEEEE
    beq  t0, t1, 1f
    li   t0, 0x100000
    li   t1, 0x5555
    sw   t1, 0(t0)
    j    2f
1:  li   a7, 93
    ecall
2:  j    2b
