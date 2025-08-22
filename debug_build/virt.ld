/* link.ld — QEMU virt RAM; compatible with stock crt0 + our __entry */
OUTPUT_ARCH(riscv)
ENTRY(__entry)   /* our trampoline is the entry, not crt0’s _start */

/* QEMU -M virt RAM */
MEMORY {
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 2G
}

/* Two PT_LOADs to avoid RWX segment warning */
PHDRS {
  text PT_LOAD FLAGS(5); /* R X */
  data PT_LOAD FLAGS(6); /* R W */
}

/* Stack and aliases */
PROVIDE(__stack_top = ORIGIN(RAM) + LENGTH(RAM));
PROVIDE(__stack     = __stack_top);

/* Small data base (optional; helps if you use .sdata/.sbss) */
PROVIDE(__global_pointer$ = ORIGIN(RAM) + 0x10000);

SECTIONS {
  /* Code + rodata */
  .text : ALIGN(4) {
    KEEP(*(.init)) KEEP(*(.init.*))
    KEEP(*(.text.__entry))      /* make sure our entry is kept */
    *(.text*) *(.rodata*) *(.rodata.*)
    _etext = .;
  } > RAM :text

  /* C++ ctor/dtor arrays */
  .init_array : ALIGN(4) {
    __init_array_start = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
    KEEP(*(.init_array))
    __init_array_end = .;
  } > RAM :text

  .fini_array : ALIGN(4) {
    __fini_array_start = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
    KEEP(*(.fini_array))
    __fini_array_end = .;
  } > RAM :text

  /* Writable data (loaded by QEMU) */
  .data : ALIGN(4) {
    _sdata = .;
    *(.data*) *(.data.*)
    . = ALIGN(4);
    _edata = .;
  } > RAM :data
  _sidata = LOADADDR(.data);

  /* Small data near gp (optional) */
  .sdata : ALIGN(4) { *(.sdata .sdata.* .gnu.linkonce.s.*) } > RAM :data

  /* Zero‑init */
  .sbss (NOLOAD) : ALIGN(4) { *(.sbss .sbss.* .gnu.linkonce.sb.*) } > RAM :data

  .bss (NOLOAD) : ALIGN(4) {
    __bss_start__ = .;
    __bss_start   = __bss_start__;   /* alias for variants that want single underscore */
    *(.bss .bss.*) *(COMMON)
    . = ALIGN(4);
    __bss_end__   = .;
    __bss_end     = __bss_end__;     /* alias */
  } > RAM :data

  . = ALIGN(8);
  _end = .;
}
