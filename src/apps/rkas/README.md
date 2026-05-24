# rkas

`rkas` is the initial Rk-C hosted RV64 assembler. It consumes assembly source
from the writable filesystem and uses the shared RKX writer to emit an
unprivileged runnable executable.

## Usage

```text
rkas <source.s> -o <output.rkx>
```

## Initial Syntax

```text
sections:    .text .rodata .data .bss
directives:  .entry .byte .asciz .zero
labels:      name:

instructions:
  li la addi add sub
  ld sd lw sw lbu sb
  beq bne j call ret ecall
```

The initial implementation uses one 4 KiB page for each section and accepts
decimal or `0x` hexadecimal immediate values. `li` supports signed 32-bit
constants and expands to one or two instructions as needed.

## Example

```asm
.text
.entry _start
_start:
  la a0, message
  li a1, 17
  li a3, 1
  ecall
  li a0, 0
  li a3, 5
  ecall

.rodata
message:
  .asciz "hello from rkas!\n"
```

`SysWrite` receives the byte length in `a1`. The newline escape is emitted as
one byte by `.asciz`, so the example passes `17` for the 16 printable
characters plus the trailing newline. The terminating zero byte is not written.
