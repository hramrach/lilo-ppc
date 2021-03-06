/*  $Id$ */
/*
 * Copyright (C) Paul Mackerras 1997.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *
 * NOTE: this code runs in 32 bit mode and is packaged as ELF32.
 */

#include <ppc_asm.h>

	.text
	/*
	 * _start is defined this way because the XCOFF loader in the OpenFirmware
	 * on the powermac expects the entry point to be a procedure descriptor.
	 */
	.globl	_coff_start
_coff_start:
	.long	_start,0,0
	
	.globl	_start
_start:
	bl	reloc_offset

reloc_offset:
	mflr	r0
	lis	r9,reloc_offset@ha
	addi	r9,r9,reloc_offset@l
	subf.	r0,r9,r0
	beq	clear_caches
	
reloc_got2:
	lis	r9,__got2_start@ha
	addi	r9,r9,__got2_start@l
	lis	r8,__got2_end@ha
	addi	r8,r8,__got2_end@l
	subf.	r8,r9,r8
	beq	clear_caches
	srwi.	r8,r8,2
	mtctr	r8
	add	r9,r0,r9
reloc_got2_loop:
	lwz	r8,0(r9)
	add	r8,r8,r0
	stw	r8,0(r9)
	addi	r9,r9,4
	bdnz	reloc_got2_loop

clear_caches:
	lis	r9,_start@ha
	addi	r9,r9,_start@l
	add	r9,r0,r9
	lis	r8,_etext@ha
	addi	r8,r8,_etext@l
	add	r8,r0,r8
1:	dcbf	r0,r9
	icbi	r0,r9
	addi	r9,r9,0x20
	cmplw	cr0,r9,r8
	blt	1b
	sync
	isync

	addi	r1,r1,-16
	rlwinm	r1,r1,0,0,27
	mr	r6,r1
	b	start

