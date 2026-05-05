MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    RAM (rwx) : ORIGIN = 0x00001000, LENGTH = 4K
}

SECTIONS {
    .text 0x00000000 : { *(.text) } > ROM
    .data 0x00001000 : { *(.data) } > RAM
}
