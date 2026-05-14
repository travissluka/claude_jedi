MPICC ?= mpicc
CFLAGS ?= -O2 -Wall

pingpong: pingpong.c
	$(MPICC) $(CFLAGS) -o $@ $<

clean:
	rm -f pingpong

.PHONY: clean
