# Rk-C Toolchain

Rk-C Toolchain provides the hosted development tools for the Rk-C operating
system. It lets programs be written, assembled, compiled, linked, and inspected
from inside a running Rk-C environment.

The toolchain is kept as a module separate from the kernel. It integrates with
an Rk-C checkout through `module.mk`, uses the public RKX executable format and
syscall ABI, and produces normal userspace applications for the Rk-C shell.

## What It Provides

| Tool | Purpose |
| --- | --- |
| `rkas` | Assemble the supported RV64 subset into RKX executables or RKO objects |
| `rkcc` | Compile the hosted C-like language into RKX executables, assembly, or RKO objects |
| `rkld` | Link one or more RKO objects into a runnable RKX executable |
| `cc` | Drive compile, assemble, object, and link workflows with a familiar frontend |
| `rkcstdlib` | Install public `rkc_*` headers and split standard-library RKO objects |
| `rkxwritecheck` | Test-only validation utility for RKX writer behavior |

Supporting libraries live under `src/lib/`:

| Library | Purpose |
| --- | --- |
| `rkx_writer` | Validated RKX image writer used by hosted tools |
| `rko_format` | Shared RKO1 object-format reader and writer |
| `libcmini` | Small hosted C library surface used by `rkcc` and `rkcstdlib` |

## Quick Start

The easiest hosted workflow is to write a C-like source file and build it with
`cc`:

```sh
edit /home/rkc/src/hello.c
cc /home/rkc/src/hello.c -o /home/rkc/bin/hello
hello
```

`cc` can also stop after assembly or object generation:

```sh
cc -S /home/rkc/src/hello.c -o /home/rkc/src/hello.s
cc -c /home/rkc/src/hello.c -o /home/rkc/src/hello.rko
```

Assembly-only programs can be built directly with `rkas`:

```sh
edit /home/rkc/src/hello.s
rkas /home/rkc/src/hello.s -o /home/rkc/bin/hello
rkxinfo /home/rkc/bin/hello
hello
```

Relocatable objects can be linked explicitly:

```sh
rkas -c /home/rkc/src/start.s -o /home/rkc/src/start.rko
rkcc -c /home/rkc/src/main.c -o /home/rkc/src/main.rko
rkld /home/rkc/src/start.rko /home/rkc/src/main.rko -o /home/rkc/bin/app
```

## Standard Library

`rkcstdlib` installs root-owned public headers under `/usr/include` and
linkable standard-library objects under `/usr/lib`:

```sh
sudo rkcstdlib --install
```

Sources that begin with public `rkc_*` include directives automatically use the
installed headers and standard libraries:

```c
#include <rkc_stdio.h>
#include <rkc_string.h>

int main() {
  char *message = "hello from stdio\n";
  write(1, message, strlen(message));
  printf("bytes=%d\n", strlen(message));
  return 0;
}
```

```sh
cc /home/rkc/src/hello.c -o /home/rkc/bin/hello
```

The current public headers are:

| Header | Functions |
| --- | --- |
| `<rkc_stdio.h>` | `puts`, `printf`, `open`, `read`, `write`, `close` |
| `<rkc_stdlib.h>` | `exit` |
| `<rkc_string.h>` | `strlen` |
| `<rkc_unistd.h>` | `getuid`, `getgid` |

Sources without public headers keep the older builtin lowering path for
compatibility.

## Rk-C Integration

When this repository is present at `modules/rkc-toolchain` in an Rk-C
workspace, the kernel build includes it through `module.mk`.

Runtime tools are packed into the normal appfs image:

```make
RKC_TOOLCHAIN_APP_NAMES := rkas rkcc rkld cc rkcstdlib
```

Validation-only tools are packed into test images:

```make
RKC_TOOLCHAIN_TEST_APP_NAMES := rkxwritecheck
```

## Documentation

| Topic | Link |
| --- | --- |
| Tool applications | [`src/apps/README.md`](src/apps/README.md) |
| `cc` driver | [`src/apps/cc/README.md`](src/apps/cc/README.md) |
| `rkcc` language surface | [`src/apps/rkcc/README.md`](src/apps/rkcc/README.md) |
| Assembler | [`src/apps/rkas/README.md`](src/apps/rkas/README.md) |
| Linker | [`src/apps/rkld/README.md`](src/apps/rkld/README.md) |
| Standard-library manual pages | [`docs/README.md`](docs/README.md) |
| Libraries | [`src/lib/README.md`](src/lib/README.md) |
| Tests | [`tests/README.md`](tests/README.md) |

## Development

In the parent Rk-C workspace, use the normal Workshop environment:

```sh
workshop run rkc-dev -- build
workshop run rkc-dev -- test
```

The app smoke test suite includes optional toolchain cases that compile,
assemble, link, install standard-library files, and execute generated RKX
programs inside QEMU.
