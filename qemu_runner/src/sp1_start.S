// From the dump of sp1 toolchain's elf


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

80130208 <__libc_fini_array>:
80130208:	ff010113          	add	sp,sp,-16
8013020c:	00812423          	sw	s0,8(sp)
80130210:	0003d797          	auipc	a5,0x3d
80130214:	6cc78793          	add	a5,a5,1740 # 8016d8dc <__do_global_dtors_aux_fini_array_entry>
80130218:	0003d417          	auipc	s0,0x3d
8013021c:	6c840413          	add	s0,s0,1736 # 8016d8e0 <_ZTVN8silkworm12_GLOBAL__N_111BlockHashesE>
80130220:	40f40433          	sub	s0,s0,a5
80130224:	00912223          	sw	s1,4(sp)
80130228:	00112623          	sw	ra,12(sp)
8013022c:	40245493          	sra	s1,s0,0x2
80130230:	02048063          	beqz	s1,80130250 <__libc_fini_array+0x48>
80130234:	ffc40413          	add	s0,s0,-4
80130238:	00f40433          	add	s0,s0,a5
8013023c:	00042783          	lw	a5,0(s0)
80130240:	fff48493          	add	s1,s1,-1
80130244:	ffc40413          	add	s0,s0,-4
80130248:	000780e7          	jalr	a5
8013024c:	fe0498e3          	bnez	s1,8013023c <__libc_fini_array+0x34>
80130250:	00c12083          	lw	ra,12(sp)
80130254:	00812403          	lw	s0,8(sp)
80130258:	00412483          	lw	s1,4(sp)
8013025c:	01010113          	add	sp,sp,16
80130260:	00008067          	ret



8012184c <__libc_init_array>:
8012184c:	ff010113          	add	sp,sp,-16
80121850:	00812423          	sw	s0,8(sp)
80121854:	01212023          	sw	s2,0(sp)
80121858:	0003e797          	auipc	a5,0x3e
8012185c:	18078793          	add	a5,a5,384 # 8015f9d8 <__preinit_array_end>
80121860:	0003e417          	auipc	s0,0x3e
80121864:	17840413          	add	s0,s0,376 # 8015f9d8 <__preinit_array_end>
80121868:	00112623          	sw	ra,12(sp)
8012186c:	00912223          	sw	s1,4(sp)
80121870:	40878933          	sub	s2,a5,s0
80121874:	02878063          	beq	a5,s0,80121894 <__libc_init_array+0x48>
80121878:	40295913          	sra	s2,s2,0x2
8012187c:	00000493          	li	s1,0
80121880:	00042783          	lw	a5,0(s0)
80121884:	00148493          	add	s1,s1,1
80121888:	00440413          	add	s0,s0,4
8012188c:	000780e7          	jalr	a5
80121890:	ff24e8e3          	bltu	s1,s2,80121880 <__libc_init_array+0x34>
80121894:	0004c797          	auipc	a5,0x4c
80121898:	04878793          	add	a5,a5,72 # 8016d8dc <__do_global_dtors_aux_fini_array_entry>
8012189c:	0004c417          	auipc	s0,0x4c
801218a0:	ff440413          	add	s0,s0,-12 # 8016d890 <__init_array_start>
801218a4:	40878933          	sub	s2,a5,s0
801218a8:	40295913          	sra	s2,s2,0x2
801218ac:	00878e63          	beq	a5,s0,801218c8 <__libc_init_array+0x7c>
801218b0:	00000493          	li	s1,0
801218b4:	00042783          	lw	a5,0(s0)
801218b8:	00148493          	add	s1,s1,1
801218bc:	00440413          	add	s0,s0,4
801218c0:	000780e7          	jalr	a5
801218c4:	ff24e8e3          	bltu	s1,s2,801218b4 <__libc_init_array+0x68>
801218c8:	00c12083          	lw	ra,12(sp)
801218cc:	00812403          	lw	s0,8(sp)
801218d0:	00412483          	lw	s1,4(sp)
801218d4:	00012903          	lw	s2,0(sp)
801218d8:	01010113          	add	sp,sp,16
801218dc:	00008067          	ret




80121798 <_sbrk_r>:
80121798:	ff010113          	add	sp,sp,-16
8012179c:	00812423          	sw	s0,8(sp)
801217a0:	00050413          	mv	s0,a0
801217a4:	00058513          	mv	a0,a1
801217a8:	d401a223          	sw	zero,-700(gp) # 8017910c <errno>
801217ac:	00112623          	sw	ra,12(sp)
801217b0:	01d1e0ef          	jal	8013ffcc <_sbrk>
801217b4:	fff00793          	li	a5,-1
801217b8:	00f50a63          	beq	a0,a5,801217cc <_sbrk_r+0x34>
801217bc:	00c12083          	lw	ra,12(sp)
801217c0:	00812403          	lw	s0,8(sp)
801217c4:	01010113          	add	sp,sp,16
801217c8:	00008067          	ret
801217cc:	d441a783          	lw	a5,-700(gp) # 8017910c <errno>
801217d0:	fe0786e3          	beqz	a5,801217bc <_sbrk_r+0x24>
801217d4:	00c12083          	lw	ra,12(sp)
801217d8:	00f42023          	sw	a5,0(s0)
801217dc:	00812403          	lw	s0,8(sp)
801217e0:	01010113          	add	sp,sp,16
801217e4:	00008067          	ret

801217e8 <_write_r>:
801217e8:	ff010113          	add	sp,sp,-16
801217ec:	00058713          	mv	a4,a1
801217f0:	00812423          	sw	s0,8(sp)
801217f4:	00060593          	mv	a1,a2
801217f8:	00050413          	mv	s0,a0
801217fc:	00068613          	mv	a2,a3
80121800:	00070513          	mv	a0,a4
80121804:	d401a223          	sw	zero,-700(gp) # 8017910c <errno>
80121808:	00112623          	sw	ra,12(sp)
8012180c:	03d1e0ef          	jal	80140048 <_write>
80121810:	fff00793          	li	a5,-1
80121814:	00f50a63          	beq	a0,a5,80121828 <_write_r+0x40>
80121818:	00c12083          	lw	ra,12(sp)
8012181c:	00812403          	lw	s0,8(sp)
80121820:	01010113          	add	sp,sp,16
80121824:	00008067          	ret
80121828:	d441a783          	lw	a5,-700(gp) # 8017910c <errno>
8012182c:	fe0786e3          	beqz	a5,80121818 <_write_r+0x30>
80121830:	00c12083          	lw	ra,12(sp)
80121834:	00f42023          	sw	a5,0(s0)
80121838:	00812403          	lw	s0,8(sp)
8012183c:	01010113          	add	sp,sp,16
80121840:	00008067          	ret



801218f0 <memmove>:
801218f0:	02a5f663          	bgeu	a1,a0,8012191c <memmove+0x2c>
801218f4:	00c58733          	add	a4,a1,a2
801218f8:	02e57263          	bgeu	a0,a4,8012191c <memmove+0x2c>
801218fc:	00c507b3          	add	a5,a0,a2
80121900:	04060663          	beqz	a2,8012194c <memmove+0x5c>
80121904:	fff74683          	lbu	a3,-1(a4)
80121908:	fff78793          	add	a5,a5,-1
8012190c:	fff70713          	add	a4,a4,-1
80121910:	00d78023          	sb	a3,0(a5)
80121914:	fef518e3          	bne	a0,a5,80121904 <memmove+0x14>
80121918:	00008067          	ret
8012191c:	00f00793          	li	a5,15
80121920:	02c7e863          	bltu	a5,a2,80121950 <memmove+0x60>
80121924:	00050793          	mv	a5,a0
80121928:	fff60693          	add	a3,a2,-1
8012192c:	0c060263          	beqz	a2,801219f0 <memmove+0x100>
80121930:	00168693          	add	a3,a3,1
80121934:	00d786b3          	add	a3,a5,a3
80121938:	0005c703          	lbu	a4,0(a1)
8012193c:	00178793          	add	a5,a5,1
80121940:	00158593          	add	a1,a1,1
80121944:	fee78fa3          	sb	a4,-1(a5)
80121948:	fed798e3          	bne	a5,a3,80121938 <memmove+0x48>
8012194c:	00008067          	ret
80121950:	00b567b3          	or	a5,a0,a1
80121954:	0037f793          	and	a5,a5,3
80121958:	08079663          	bnez	a5,801219e4 <memmove+0xf4>
8012195c:	ff060893          	add	a7,a2,-16
80121960:	ff08f893          	and	a7,a7,-16
80121964:	01088893          	add	a7,a7,16
80121968:	011506b3          	add	a3,a0,a7
8012196c:	00058713          	mv	a4,a1
80121970:	00050793          	mv	a5,a0
80121974:	00072803          	lw	a6,0(a4)
80121978:	01070713          	add	a4,a4,16
8012197c:	01078793          	add	a5,a5,16
80121980:	ff07a823          	sw	a6,-16(a5)
80121984:	ff472803          	lw	a6,-12(a4)
80121988:	ff07aa23          	sw	a6,-12(a5)
8012198c:	ff872803          	lw	a6,-8(a4)
80121990:	ff07ac23          	sw	a6,-8(a5)
80121994:	ffc72803          	lw	a6,-4(a4)
80121998:	ff07ae23          	sw	a6,-4(a5)
8012199c:	fcd79ce3          	bne	a5,a3,80121974 <memmove+0x84>
801219a0:	00c67813          	and	a6,a2,12
801219a4:	011585b3          	add	a1,a1,a7
801219a8:	00f67713          	and	a4,a2,15
801219ac:	04080463          	beqz	a6,801219f4 <memmove+0x104>
801219b0:	ffc70813          	add	a6,a4,-4
801219b4:	ffc87813          	and	a6,a6,-4
801219b8:	00480813          	add	a6,a6,4
801219bc:	010687b3          	add	a5,a3,a6
801219c0:	00058713          	mv	a4,a1
801219c4:	00072883          	lw	a7,0(a4)
801219c8:	00468693          	add	a3,a3,4
801219cc:	00470713          	add	a4,a4,4
801219d0:	ff16ae23          	sw	a7,-4(a3)
801219d4:	fef698e3          	bne	a3,a5,801219c4 <memmove+0xd4>
801219d8:	00367613          	and	a2,a2,3
801219dc:	010585b3          	add	a1,a1,a6
801219e0:	f49ff06f          	j	80121928 <memmove+0x38>
801219e4:	fff60693          	add	a3,a2,-1
801219e8:	00050793          	mv	a5,a0
801219ec:	f45ff06f          	j	80121930 <memmove+0x40>
801219f0:	00008067          	ret
801219f4:	00070613          	mv	a2,a4
801219f8:	f31ff06f          	j	80121928 <memmove+0x38>

801219fc <memset>:
801219fc:	00f00313          	li	t1,15
80121a00:	00050713          	mv	a4,a0
80121a04:	02c37e63          	bgeu	t1,a2,80121a40 <memset+0x44>
80121a08:	00f77793          	and	a5,a4,15
80121a0c:	0a079063          	bnez	a5,80121aac <memset+0xb0>
80121a10:	08059263          	bnez	a1,80121a94 <memset+0x98>
80121a14:	ff067693          	and	a3,a2,-16
80121a18:	00f67613          	and	a2,a2,15
80121a1c:	00e686b3          	add	a3,a3,a4
80121a20:	00b72023          	sw	a1,0(a4)
80121a24:	00b72223          	sw	a1,4(a4)
80121a28:	00b72423          	sw	a1,8(a4)
80121a2c:	00b72623          	sw	a1,12(a4)
80121a30:	01070713          	add	a4,a4,16
80121a34:	fed766e3          	bltu	a4,a3,80121a20 <memset+0x24>
80121a38:	00061463          	bnez	a2,80121a40 <memset+0x44>
80121a3c:	00008067          	ret
80121a40:	40c306b3          	sub	a3,t1,a2
80121a44:	00269693          	sll	a3,a3,0x2
80121a48:	00000297          	auipc	t0,0x0
80121a4c:	005686b3          	add	a3,a3,t0
80121a50:	00c68067          	jr	12(a3)
80121a54:	00b70723          	sb	a1,14(a4)
80121a58:	00b706a3          	sb	a1,13(a4)
80121a5c:	00b70623          	sb	a1,12(a4)
80121a60:	00b705a3          	sb	a1,11(a4)
80121a64:	00b70523          	sb	a1,10(a4)
80121a68:	00b704a3          	sb	a1,9(a4)
80121a6c:	00b70423          	sb	a1,8(a4)
80121a70:	00b703a3          	sb	a1,7(a4)
80121a74:	00b70323          	sb	a1,6(a4)
80121a78:	00b702a3          	sb	a1,5(a4)
80121a7c:	00b70223          	sb	a1,4(a4)
80121a80:	00b701a3          	sb	a1,3(a4)
80121a84:	00b70123          	sb	a1,2(a4)
80121a88:	00b700a3          	sb	a1,1(a4)
80121a8c:	00b70023          	sb	a1,0(a4)
80121a90:	00008067          	ret
80121a94:	0ff5f593          	zext.b	a1,a1
80121a98:	00859693          	sll	a3,a1,0x8
80121a9c:	00d5e5b3          	or	a1,a1,a3
80121aa0:	01059693          	sll	a3,a1,0x10
80121aa4:	00d5e5b3          	or	a1,a1,a3
80121aa8:	f6dff06f          	j	80121a14 <memset+0x18>
80121aac:	00279693          	sll	a3,a5,0x2
80121ab0:	00000297          	auipc	t0,0x0
80121ab4:	005686b3          	add	a3,a3,t0
80121ab8:	00008293          	mv	t0,ra
80121abc:	fa0680e7          	jalr	-96(a3)
80121ac0:	00028093          	mv	ra,t0
80121ac4:	ff078793          	add	a5,a5,-16
80121ac8:	40f70733          	sub	a4,a4,a5
80121acc:	00f60633          	add	a2,a2,a5
80121ad0:	f6c378e3          	bgeu	t1,a2,80121a40 <memset+0x44>
80121ad4:	f3dff06f          	j	80121a10 <memset+0x14>

80121ad8 <memcpy>:
80121ad8:	00a5c7b3          	xor	a5,a1,a0
80121adc:	0037f793          	and	a5,a5,3
80121ae0:	00c508b3          	add	a7,a0,a2
80121ae4:	06079463          	bnez	a5,80121b4c <memcpy+0x74>
80121ae8:	00300793          	li	a5,3
80121aec:	06c7f063          	bgeu	a5,a2,80121b4c <memcpy+0x74>
80121af0:	00357793          	and	a5,a0,3
80121af4:	00050713          	mv	a4,a0
80121af8:	06079a63          	bnez	a5,80121b6c <memcpy+0x94>
80121afc:	ffc8f613          	and	a2,a7,-4
80121b00:	40e606b3          	sub	a3,a2,a4
80121b04:	02000793          	li	a5,32
80121b08:	08d7ce63          	blt	a5,a3,80121ba4 <memcpy+0xcc>
80121b0c:	00058693          	mv	a3,a1
80121b10:	00070793          	mv	a5,a4
80121b14:	02c77863          	bgeu	a4,a2,80121b44 <memcpy+0x6c>
80121b18:	0006a803          	lw	a6,0(a3)
80121b1c:	00478793          	add	a5,a5,4
80121b20:	00468693          	add	a3,a3,4
80121b24:	ff07ae23          	sw	a6,-4(a5)
80121b28:	fec7e8e3          	bltu	a5,a2,80121b18 <memcpy+0x40>
80121b2c:	fff60793          	add	a5,a2,-1
80121b30:	40e787b3          	sub	a5,a5,a4
80121b34:	ffc7f793          	and	a5,a5,-4
80121b38:	00478793          	add	a5,a5,4
80121b3c:	00f70733          	add	a4,a4,a5
80121b40:	00f585b3          	add	a1,a1,a5
80121b44:	01176863          	bltu	a4,a7,80121b54 <memcpy+0x7c>
80121b48:	00008067          	ret
80121b4c:	00050713          	mv	a4,a0
80121b50:	05157863          	bgeu	a0,a7,80121ba0 <memcpy+0xc8>
80121b54:	0005c783          	lbu	a5,0(a1)
80121b58:	00170713          	add	a4,a4,1
80121b5c:	00158593          	add	a1,a1,1
80121b60:	fef70fa3          	sb	a5,-1(a4)
80121b64:	fee898e3          	bne	a7,a4,80121b54 <memcpy+0x7c>
80121b68:	00008067          	ret
80121b6c:	0005c683          	lbu	a3,0(a1)
80121b70:	00170713          	add	a4,a4,1
80121b74:	00377793          	and	a5,a4,3
80121b78:	fed70fa3          	sb	a3,-1(a4)
80121b7c:	00158593          	add	a1,a1,1
80121b80:	f6078ee3          	beqz	a5,80121afc <memcpy+0x24>
80121b84:	0005c683          	lbu	a3,0(a1)
80121b88:	00170713          	add	a4,a4,1
80121b8c:	00377793          	and	a5,a4,3
80121b90:	fed70fa3          	sb	a3,-1(a4)
80121b94:	00158593          	add	a1,a1,1
80121b98:	fc079ae3          	bnez	a5,80121b6c <memcpy+0x94>
80121b9c:	f61ff06f          	j	80121afc <memcpy+0x24>
80121ba0:	00008067          	ret
80121ba4:	ff010113          	add	sp,sp,-16
80121ba8:	00812623          	sw	s0,12(sp)
80121bac:	02000413          	li	s0,32
80121bb0:	0005a383          	lw	t2,0(a1)
80121bb4:	0045a283          	lw	t0,4(a1)
80121bb8:	0085af83          	lw	t6,8(a1)
80121bbc:	00c5af03          	lw	t5,12(a1)
80121bc0:	0105ae83          	lw	t4,16(a1)
80121bc4:	0145ae03          	lw	t3,20(a1)
80121bc8:	0185a303          	lw	t1,24(a1)
80121bcc:	01c5a803          	lw	a6,28(a1)
80121bd0:	0205a683          	lw	a3,32(a1)
80121bd4:	02470713          	add	a4,a4,36
80121bd8:	40e607b3          	sub	a5,a2,a4
80121bdc:	fc772e23          	sw	t2,-36(a4)
80121be0:	fe572023          	sw	t0,-32(a4)
80121be4:	fff72223          	sw	t6,-28(a4)
80121be8:	ffe72423          	sw	t5,-24(a4)
80121bec:	ffd72623          	sw	t4,-20(a4)
80121bf0:	ffc72823          	sw	t3,-16(a4)
80121bf4:	fe672a23          	sw	t1,-12(a4)
80121bf8:	ff072c23          	sw	a6,-8(a4)
80121bfc:	fed72e23          	sw	a3,-4(a4)
80121c00:	02458593          	add	a1,a1,36
80121c04:	faf446e3          	blt	s0,a5,80121bb0 <memcpy+0xd8>
80121c08:	00058693          	mv	a3,a1
80121c0c:	00070793          	mv	a5,a4
80121c10:	02c77863          	bgeu	a4,a2,80121c40 <memcpy+0x168>
80121c14:	0006a803          	lw	a6,0(a3)
80121c18:	00478793          	add	a5,a5,4
80121c1c:	00468693          	add	a3,a3,4
80121c20:	ff07ae23          	sw	a6,-4(a5)
80121c24:	fec7e8e3          	bltu	a5,a2,80121c14 <memcpy+0x13c>
80121c28:	fff60793          	add	a5,a2,-1
80121c2c:	40e787b3          	sub	a5,a5,a4
80121c30:	ffc7f793          	and	a5,a5,-4
80121c34:	00478793          	add	a5,a5,4
80121c38:	00f70733          	add	a4,a4,a5
80121c3c:	00f585b3          	add	a1,a1,a5
80121c40:	01176863          	bltu	a4,a7,80121c50 <memcpy+0x178>
80121c44:	00c12403          	lw	s0,12(sp)
80121c48:	01010113          	add	sp,sp,16
80121c4c:	00008067          	ret
80121c50:	0005c783          	lbu	a5,0(a1)
80121c54:	00170713          	add	a4,a4,1
80121c58:	00158593          	add	a1,a1,1
80121c5c:	fef70fa3          	sb	a5,-1(a4)
80121c60:	fee882e3          	beq	a7,a4,80121c44 <memcpy+0x16c>
80121c64:	0005c783          	lbu	a5,0(a1)
80121c68:	00170713          	add	a4,a4,1
80121c6c:	00158593          	add	a1,a1,1
80121c70:	fef70fa3          	sb	a5,-1(a4)
80121c74:	fce89ee3          	bne	a7,a4,80121c50 <memcpy+0x178>
80121c78:	fcdff06f          	j	80121c44 <memcpy+0x16c>