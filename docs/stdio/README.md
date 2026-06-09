# rkc_stdio.h

`<rkc_stdio.h>` declares the hosted standard I/O and file-descriptor helpers
installed by `rkcstdlib --install`.

## Functions

| Function | Summary |
| --- | --- |
| [`puts`](puts.md) | Write a NUL-terminated string to stdout |
| [`printf`](printf.md) | Format a small set of values to stdout |
| [`open`](open.md) | Open a filesystem path and return a file descriptor |
| [`read`](read.md) | Read bytes from a file descriptor into a buffer |
| [`write`](write.md) | Write bytes from a buffer to a file descriptor |
| [`close`](close.md) | Close an open file descriptor |

## Header

```c
#include <rkc_stdio.h>
```

When a source begins with a public `rkc_*` include, `rkcc` automatically uses
the installed `/usr/include` header and `cc` automatically links the matching
standard library RKO objects.
