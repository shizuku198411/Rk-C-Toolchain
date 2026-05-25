# rkas

`rkas` is the initial Rk-C hosted RV64 assembler. It consumes assembly source
from the writable filesystem and uses the shared RKX writer to emit an
unprivileged runnable executable.

## Usage

```text
rkas <source.s> -o <output.rkx>
```

## Supported Syntax

```text
sections:    .text .rodata .data .bss
directives:  .entry .byte .asciz .zero
labels:      name:

instructions:
  li la addi andi ori xori slti sltiu
  add sub mul div rem and or xor slt sltu
  sll srl sra slli srli srai
  ld sd lw sw lh lhu sh lb lbu sb
  beq bne blt bge bltu bgeu j call ret ecall
```

The assembler accepts decimal or `0x` hexadecimal immediate values. Each
section may contain up to 16 KiB, and output section virtual addresses are
laid out on page boundaries based on the section data that was actually
emitted. `li` supports signed 32-bit constants and expands to one or two
instructions as needed.

The multiplication and division operations use the RV64M extension. Programs
generated through the hosted toolchain therefore target the Rk-C RV64IM
runtime baseline.

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
