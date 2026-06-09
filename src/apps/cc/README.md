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
```

Executable builds compile one C translation unit to a temporary RKO object and
link it through `rkld`. Existing RKO objects may be supplied alongside the C
source or linked without a C source.

After `rkcstdlib --install`, source files that begin with public `rkc_*`
headers automatically use `/usr/include` and link `/usr/lib/rkc_stdio.rko`,
`/usr/lib/rkc_stdlib.rko`, `/usr/lib/rkc_string.rko`, and
`/usr/lib/rkc_unistd.rko`. Programs using these headers therefore reach
`puts`, file-descriptor I/O, string length, identity queries, and process exit
through named library objects rather than compiler-emitted syscall sequences.
The explicit `-I/usr/include` option is still accepted for compatibility.
