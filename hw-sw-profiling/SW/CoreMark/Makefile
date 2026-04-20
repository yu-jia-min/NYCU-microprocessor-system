# ======================================================================
#  This Makefile builds an application *.elf for Aquila.
#
#  Chun-Jen Tsai, Aug/28/2025
# ======================================================================
RISCV_ABI = -march=rv32ima_zicsr_zifencei -mabi=ilp32
GCC_LIB = rv32im/ilp32

CROSS = riscv32-unknown-elf
CCPATH = $(RISCV)/bin

CC = $(CCPATH)/$(CROSS)-gcc
LD = $(CCPATH)/$(CROSS)-ld
AR = $(CCPATH)/$(CROSS)-ar
OD = $(CCPATH)/$(CROSS)-objdump
SP = $(CCPATH)/$(CROSS)-strip

GCCVERSION = $(shell $(CC) --version | grep gcc | sed 's/^.* //g')

LIBC = ../elibc
LIBC_OBJS = $(LIBC)/crt0.o $(LIBC)/stdio.o $(LIBC)/stdlib.o $(LIBC)/string.o $(LIBC)/time.o $(LIBC)/uart.o

CCFLAGS = -Wall -O3 -I$(LIBC) -fno-builtin $(RISCV_ABI) -mstrict-align -fno-inline-small-functions
XCFLAGS = -DITERATIONS=0 -DUSE_CLOCK=1
LDFLAGS = -L. -Map=$*.map
LD_GCC_LIB = -L$(RISCV)/lib/gcc/riscv32-unknown-elf/$(GCCVERSION)/$(GCC_LIB) -lgcc

OCFLAGS = -O binary
ODFLAGS = -d

PROJ = coremark
OBJS = core_main.o core_portme.o core_util.o core_list_join.o core_matrix.o core_state.o

FLAGS_STR = "$(CCFLAGS) $(XCFLAGS)"

tcm:
	make MEM_TYPE=tcm $(PROJ).elf

ddr:
	make MEM_TYPE=ddr $(PROJ).elf

clean:
	rm -f *.elf *.objdump *.map *.o *.a

%.o: %.c
	$(CC) $(CCFLAGS) $(XCFLAGS) $(LCFLAGS) -DFLAGS_STR=\"$(FLAGS_STR)\" -c $< -o $@

libelibc.a : $(LIBC_OBJS)
	$(AR) r libelibc.a $(LIBC_OBJS)
	rm $^

# 就是改這裡
%.elf: XCFLAGS = -DITERATIONS=0 -DUSE_CLOCK=1
#
%.elf: $(OBJS) libelibc.a
	$(LD) $(LDFLAGS) -T$*_$(MEM_TYPE).ld $(OBJS) -lelibc $(LD_GCC_LIB) -o $@
	$(OD) $(ODFLAGS) $@ > $*.objdump
	$(SP) -g $@
	rm $^

