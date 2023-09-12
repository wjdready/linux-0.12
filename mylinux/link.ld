
ENTRY(_start)

/* MEMORY
{
    BIOSRAM (rwx) : ORIGIN = 0x7c00, LENGTH = 0x200
    BOOTRAM (rwx) : ORIGIN = 0x9000, LENGTH = 0x1000
} */

SECTIONS
{
    /* . = 0x7c00; */
    . = 0;
    .text : {
        *(.text)
        *(.text.helper)
    }

    /* . = 0x7dfe; */
    . = 0x1fe;
    .boot_end : {
        *(.boot_end)
    }
}
