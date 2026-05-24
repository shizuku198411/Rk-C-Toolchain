# Rk-C Toolchain

Rk-C Toolchain is the userspace development tool repository for the Rk-C
operating system. Its goal is to make it possible to write, build, inspect,
and eventually link programs from inside a running Rk-C environment.

The repository is developed independently from the kernel and integrates with
an Rk-C checkout through `module.mk`. Toolchain programs use the public RKX
executable and syscall interfaces supplied by Rk-C; kernel internals do not
depend on toolchain implementation details.

## Components

| Status | Component | Purpose |
| --- | --- | --- |
| Available | `src/apps/rkas` | RV64 assembler that emits runnable RKX applications |
| Available | `src/lib/rkx_writer` | Shared validated RKX image writer |
| Test only | `src/apps/rkxwritecheck` | RKX writer integration and validation utility |
| Planned | `src/apps/rkcc` | Small C-like compiler frontend |
| Planned | `src/lib/libcmini` | Minimal application programming library |
| Planned | `src/apps/rkld` | Object and library linker |
| Planned | `src/lib/object` | Shared object-format representation |

## Rk-C Integration

When the repository is present in an Rk-C workspace, the kernel build may
include `module.mk`. Runtime tools are registered in `RKC_TOOLCHAIN_APP_NAMES`
and are packed into the ordinary appfs image. Validation utilities are
registered separately in `RKC_TOOLCHAIN_TEST_APP_NAMES` and appear only in
test images.

```make
RKC_TOOLCHAIN_APP_NAMES := rkas
RKC_TOOLCHAIN_TEST_APP_NAMES := rkxwritecheck
```

## Running on Rk-C

The currently available hosted workflow is:

```sh
edit /home/rkc/src/hello.s

## write in assembly ##
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

.data
seed:
  .byte 0x2a

.bss
scratch:
  .zero 16
#######################

rkas /home/rkc/src/hello.s -o /home/rkc/bin/hello
rkxinfo /home/rkc/bin/hello
hello
```
