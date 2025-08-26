ENTRY(start)

SECTIONS {
    . = 0x10000000;

    .text :{
        KEEP(*(.text.start));
        *(.text .text.*);
    }

    .rodata : ALIGN(4) {
        *(.rodata .rodata.*);
    }

    .data : ALIGN(4) {
        *(.data .data.*);
    }

    /* the stack in bss is mandatory otherwise
       whole section will be stripped */
    .bss : ALIGN(4) {
        *(.bss .bss.* .sbss .sbss.*);

        . = ALIGN(16);
        . += 64 * 1024;
        __user_stack_top = .;

       ASSERT(. < 0x18000000, "too large executable");
    }
}
