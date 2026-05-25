# rkcstdlib

`rkcstdlib` installs public C-like development headers and linkable userspace
standard libraries for the hosted Rk-C toolchain.

The command is restricted to `uid=0` because it manages root-owned files in
`/usr/include` and `/usr/lib`:

```sh
sudo rkcstdlib --install
```

The installation keeps API ownership explicit:

| Header | Object library | Exported functions |
| --- | --- | --- |
| `/usr/include/rkc_stdio.h` | `/usr/lib/rkc_stdio.rko` | `puts`, `open`, `read`, `write`, `close` |
| `/usr/include/rkc_stdlib.h` | `/usr/lib/rkc_stdlib.rko` | `exit` |
| `/usr/include/rkc_string.h` | `/usr/lib/rkc_string.rko` | `strlen` |
| `/usr/include/rkc_unistd.h` | `/usr/lib/rkc_unistd.rko` | `getuid`, `getgid` |

`puts` is deliberately linked through `strlen` and `write`, so standard
library objects exercise normal cross-object symbol resolution.
