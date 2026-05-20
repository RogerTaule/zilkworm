.section .text.init,"ax",@progbits
.global _start
.type _start, @function
_start:
    .option push
    .option norelax
    la gp, _global_pointer
    .option pop
    la sp, _init_stack_top
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
