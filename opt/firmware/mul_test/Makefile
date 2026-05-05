CROSS ?= riscv64-unknown-elf
CC    := $(CROSS)-gcc
OBJCOPY := $(CROSS)-objcopy

CFLAGS  := -march=rv32im -mabi=ilp32 -nostartfiles -nostdlib
LDFLAGS := -Wl,-T,link.ld

all: mul_test.hex mul_test.bin

mul_test.elf: mul_test.S link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ mul_test.S

mul_test.bin: mul_test.elf
	$(OBJCOPY) -O binary $< $@

# Byte-oriented hex file for $readmemh into byte-addressed memory
mul_test.hex: mul_test.bin
	od -An -tx1 -v $< | tr -s ' ' '\n' | grep -E '^[0-9a-f]{2}$$' > $@

clean:
	rm -f *.elf *.hex *.bin
