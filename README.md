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
| Available | `src/apps/rkas` | RV64IM subset assembler emitting RKX or relocatable RKO output |
| Available | `src/lib/rkx_writer` | Shared validated RKX image writer |
| Test only | `src/apps/rkxwritecheck` | RKX writer integration and validation utility |
| Available | `src/apps/rkcc` | Small C-like frontend producing RKX or RKO via `rkas` |
| Available | `src/lib/libcmini` | Initial builtin libc-mini API lowered by `rkcc` |
| Available | `src/apps/rkld` | RKO object linker producing runnable RKX applications |
| Available | `src/lib/rko_format` | Shared RKO1 object-format reader and writer |
| Available | `src/apps/cc` | Conventional compiler driver coordinating `rkcc` and `rkld` |
| Available | `src/apps/rkcstdlib` | Root-owned `/usr/include/rkc.h` and `/usr/lib/librkc.rko` installer |

## Rk-C Integration

When the repository is present in an Rk-C workspace, the kernel build may
include `module.mk`. Runtime tools are registered in `RKC_TOOLCHAIN_APP_NAMES`
and are packed into the ordinary appfs image. Validation utilities are
registered separately in `RKC_TOOLCHAIN_TEST_APP_NAMES` and appear only in
test images.

```make
RKC_TOOLCHAIN_APP_NAMES := rkas rkcc rkld cc rkcstdlib
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

The hosted C-like workflow is also available:

```sh
edit /home/rkc/src/hello.c
rkcc /home/rkc/src/hello.c -o /home/rkc/bin/hello
hello
```

Relocatable objects can be linked from one or more modules:

```sh
rkas -c /home/rkc/src/start.s -o /home/rkc/src/start.rko
rkcc -c /home/rkc/src/main.c -o /home/rkc/src/main.rko
rkld /home/rkc/src/start.rko /home/rkc/src/main.rko -o /home/rkc/bin/app
```

Applications can now use the driver frontend without spelling out backend tools:

```sh
cc /home/rkc/src/hello.c -o /home/rkc/bin/hello
cc -S /home/rkc/src/hello.c -o /home/rkc/src/hello.s
cc -c /home/rkc/src/hello.c -o /home/rkc/src/hello.rko
cc /home/rkc/src/hello.rko -o /home/rkc/bin/hello
```

The installed standard library workflow is:

```sh
sudo rkcstdlib --install
edit /home/rkc/src/hello.c
cc -I/usr/include /home/rkc/src/hello.c -o /home/rkc/bin/hello
```

A source beginning with `#include <rkc.h>` emits linker-resolved calls for
`puts`, `strlen`, `write`, and `exit`, which `cc` resolves automatically from
`/usr/lib/librkc.rko`. The remaining initial libc-mini operations (`read`,
`open`, `close`, `getuid`, and `getgid`) keep their compiler builtin lowering
during the staged standard-library migration.
