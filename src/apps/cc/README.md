# cc

`cc` is the Rk-C hosted compiler driver. It presents a conventional build
interface while delegating C-like compilation to `rkcc` and final object
linking to `rkld`.

## Usage

```sh
cc input.c -o output.rkx
cc -S input.c -o output.s
cc -c input.c -o output.rko
cc input.c support.rko -o output.rkx
cc -I/usr/include input.c -o output.rkx
```

Executable builds compile one C translation unit to a temporary RKO object and
link it through `rkld`. Existing RKO objects may be supplied alongside the C
source or linked without a C source.

After `sudo rkcstdlib --install`, `-I/usr/include` enables the public
`#include <rkc.h>` interface and automatically links
`/usr/lib/librkc.rko`. The first linked library surface is `puts`, `strlen`,
`write`, and `exit`; other existing compiler-known calls remain available
during this staged migration.
