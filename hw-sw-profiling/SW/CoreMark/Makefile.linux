# ======================================================================
#  This Makefile builds the CoreMark ELF file for Aquila.
#
#  Chun-Jen Tsai, Jan/12/2020
# ======================================================================

CC = gcc

CCFLAGS = -O2 -pg -fno-inline-small-functions
LCFLAGS = -Wall -I. -lm
XCFLAGS = -DITERATIONS=0

FLAGS_STR = "$(CCFLAGS) $(XCFLAGS)"
CFLAGS = $(CCFLAGS) $(LCFLAGS) $(XCFLAGS) -DFLAGS_STR=\"$(FLAGS_STR)\"

PROJ = coremark
OBJS = core_main.o core_portme.o core_util.o core_list_join.o core_matrix.o core_state.o

coremark: $(OBJS)
	$(CC) -o $@ $(CFLAGS) $(OBJS)

clean:
	rm -f coremark *.o gmon.out

