/* src/entry.S — minimal trampoline for stock crt0
 * -rv32im only (no CSR/WFI)
 * Requires from link.ld:  __stack_top  (top of RAM)
 * Optional: __global_pointer$  (if present, we'll set gp)
 */
    .section .text.entry
    .globl __entry
    .option  norvc

__entry:
    /* 1) set a sane stack near top of RAM */
    la      sp, __stack_top
    addi    sp, sp, -16       /* room for argc, argv[0], alignment */

    /* 2) fake argc/argv for crt0 */
    sw      zero,  0(sp)      /* argc = 0 */
    sw      zero,  4(sp)      /* argv[0] = NULL */

    /* 3) optional gp (harmless if symbol missing) */
    .weak   __global_pointer$
    la      gp, __global_pointer$

    /* 4) hand off to toolchain crt0 */
    /* j       _start            /* provided by crt0.o */

    auipc	gp,0x10
    mv	gp,gp
    auipc	a0,0x32a
    addi	a0,a0,72 
    auipc	a2,0x32d
    addi	a2,a2,-544 
    sub	a2,a2,a0
    li	a1,0
    lw	a0,0(sp)
    j	 main
    auipc	t1,0x2ad
    jr	-384(t1)

    /*
    auipc	ra,0x2be
    jalr	-452(ra) 
    auipc	a0,0x2be
    addi	a0,a0,-896 
    auipc	ra,0x2ad
    jalr	-628(ra) 
    auipc	ra,0x2be
    jalr	-1052(ra) 
    lw	a0,0(sp)
    addi	a1,sp,4
    li	a2,0
    j	 main
    auipc	t1,0x2ad
    jr	-384(t1)
    */