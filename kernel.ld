/* define entry point */
ENTRY(boot)

/* define kernel section structure */
/* alignment will be 32 bits */
SECTIONS {
    . = 0x80200000;

    .text :{
        KEEP(*(.text.boot));
        *(.text .text.*);
    }

    .rodata : ALIGN(4) {
        *(.rodata .rodata.*);
    }

    .data : ALIGN(4) {
        *(.data .data.*);
    }

    .bss : ALIGN(4) {
        __bss = .;
        *(.bss .bss.* .sbss .sbss.*);
        __bss_end = .;
    }

    /* 128 KB stack size */
    . = ALIGN(4);
    . += 128 * 1024;
    __stack_top = .;

    /* alignment on heap is page size */
    /* 64 MB heap size */
    . = ALIGN(4096);
    __heap = .;
    . += 64 * 1024 * 1024;
    __heap_end = .;
}
