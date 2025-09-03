/* define entry point */
ENTRY(boot)

/* define kernel section structure */
/* alignment will be 32 bits */
SECTIONS {
    . = 0x80200000;
    __kernel_base = .;

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

    . = ALIGN(4);
    __heap = .;
    . += 64 * 1024 * 1024;
    __heap_end = .;

    /* page align since used by page allocator */
    . = ALIGN(4096);
    __free_ram = .;
    . += 128 * 1024 * 1024;
    __free_ram_end = .;
}
