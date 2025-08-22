OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

/* Top-of-RAM stack pointer for startup.S */
PROVIDE(__stack_top = ORIGIN(RAM) + LENGTH(RAM));
PROVIDE(__stack     = __stack_top);

/* Small-data window around gp; keep sdata/sbss within +/- 2KB of gp */
PROVIDE(__global_pointer$ = ORIGIN(RAM) + 0x10000);


SECTIONS
{
  .text : ALIGN(4)
  {
    KEEP(*(.text._start))        /* crt0 entry */
    *(.text*) *(.rodata*)
    _etext = .;
  } > RAM

  /* C++ static constructors / destructors */
  .init_array : ALIGN(4)
  {
    __init_array_start = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
    KEEP(*(.init_array))
    __init_array_end = .;
  } > RAM

  .fini_array : ALIGN(4)
  {
    __fini_array_start = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
    KEEP(*(.fini_array))
    __fini_array_end = .;
  } > RAM

  .data : ALIGN(4)
  {
    _sdata = .;
    *(.data*)
    . = ALIGN(4);
    _edata = .;
  } > RAM AT > RAM
  _sidata = LOADADDR(.data);

  .bss (NOLOAD) : ALIGN(4)
  {
    __bss_start = .;
    *(.bss*) *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > RAM

  /* Optional place to park symbols; no bytes emitted */
  . = ALIGN(4);
  _end = .;
}
