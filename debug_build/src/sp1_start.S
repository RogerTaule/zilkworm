80007844 <_start>:
80007844:	00172197          	auipc	gp,0x172
80007848:	b8418193          	add	gp,gp,-1148 # 801793c8 <__global_pointer$>
8000784c:	a2e18513          	add	a0,gp,-1490 # 80178df6 <__bss_start>
80007850:	00174617          	auipc	a2,0x174
80007854:	4bc60613          	add	a2,a2,1212 # 8017bd0c <__BSS_END__>
80007858:	40a60633          	sub	a2,a2,a0
8000785c:	00000593          	li	a1,0
80007860:	0011a097          	auipc	ra,0x11a
80007864:	19c080e7          	jalr	412(ra) # 801219fc <memset>
80007868:	0011b517          	auipc	a0,0x11b
8000786c:	a6850513          	add	a0,a0,-1432 # 801222d0 <atexit>
80007870:	00050a63          	beqz	a0,80007884 <_start+0x40>
80007874:	00129517          	auipc	a0,0x129
80007878:	99450513          	add	a0,a0,-1644 # 80130208 <__libc_fini_array>
8000787c:	0011b097          	auipc	ra,0x11b
80007880:	a54080e7          	jalr	-1452(ra) # 801222d0 <atexit>
80007884:	0011a097          	auipc	ra,0x11a
80007888:	fc8080e7          	jalr	-56(ra) # 8012184c <__libc_init_array>
8000788c:	00012503          	lw	a0,0(sp)
80007890:	00410593          	add	a1,sp,4
80007894:	00000613          	li	a2,0
80007898:	ed1fa0ef          	jal	80002768 <main>
8000789c:	e89f806f          	j	80000724 <exit>