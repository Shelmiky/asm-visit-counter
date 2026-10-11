.PHONY: all test clean

all: program

program: counter.o
	ld -o $@ $<

counter.o: counter.asm
	nasm -f elf64 -Werror -o $@ $<

test: program
	python3 check.py

clean:
	rm -f counter.o program
