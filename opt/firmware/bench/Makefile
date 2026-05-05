CROSS ?= riscv64-unknown-elf
CC    := $(CROSS)-gcc
OBJCOPY := $(CROSS)-objcopy

CFLAGS  := -march=rv32im -mabi=ilp32 -nostartfiles -nostdlib
LDFLAGS := -Wl,-T,link.ld

all: bench.hex bench.bin

bench.elf: bench.S link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ bench.S

bench.bin: bench.elf
	$(OBJCOPY) -O binary $< $@

bench.hex: bench.bin
	od -An -tx1 -v $< | tr -s ' ' '\n' | grep -E '^[0-9a-f]{2}$$' > $@

clean:
	rm -f *.elf *.hex *.bin
