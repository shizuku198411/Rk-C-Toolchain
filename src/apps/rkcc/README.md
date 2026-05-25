# rkcc

`rkcc` is a small C-like compiler frontend hosted on Rk-C. It reads a single
source file, emits assembly into a temporary file, and invokes `rkas` to
produce either an unprivileged RKX executable or an RKO object linked later by `rkld`.

## Usage

```text
rkcc <source.c> -o <output.rkx>
rkcc -S <source.c> -o <output.s>
rkcc -c <source.c> -o <output.rko>
rkcc -I/usr/include -c <source.c> -o <output.rko>
```

The `-S` form is used by the higher-level `cc` driver when the user requests
compiler-generated assembly without assembling or linking it.

## Supported Language Surface

```text
translation unit:  int main() { ... }
local types:       int, char * initialized from a string literal
statements:        declarations, assignment, puts, exit, if/else, while, return
int expressions:   literals, locals, unary -, +, -, *, /, %, shifts
comparisons:       ==, !=, <, <=, >, >=
bit operations:    &, ^, |
strings:           quoted literals with \n, \r, \t, \0, \\, and \" escapes
libc-mini:         write, read, open, close, puts, strlen, getuid, getgid, exit
buffers:           char buffer[N] writable storage for read
```

Without a header include, libc-mini calls retain their early builtin lowering
for compatibility. A source file may begin with any combination of
`#include <rkc_stdio.h>`, `#include <rkc_stdlib.h>`,
`#include <rkc_string.h>`, and `#include <rkc_unistd.h>` and be built with
`-I/usr/include`. In that mode, all supported libc-mini operations emit
external calls resolved from split standard library RKO objects by `cc`.
General headers, declaration-based type checking, pointer dereference, and
multi-file compilation are not implemented yet.

## Internal Layout

```text
internal/source_tokens.nim       lexical analysis and token definitions
internal/compiler_context.nim    parser state, local slots, assembly helpers
internal/expression_codegen.nim  expressions and libc-mini builtin lowering
internal/statement_codegen.nim   declarations, blocks, and control flow
internal/compiler.nim            translation-unit entry and diagnostics
internal/asm_output.nim          bounded generated assembly buffer
```

## Example

```c
int main() {
  char *message = "hello from rkcc!\n";
  puts(message);
  return 0;
}
```

```sh
rkcc /home/rkc/src/hello.c -o /home/rkc/bin/hello
hello
```
