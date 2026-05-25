# rkcc

`rkcc` is a small C-like compiler frontend hosted on Rk-C. It reads a single
source file, emits assembly into a temporary file, and invokes `rkas` to
produce an unprivileged RKX executable.

## Usage

```text
rkcc <source.c> -o <output.rkx>
```

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

The libc-mini calls are currently compiler builtins lowered directly to the
Rk-C syscall ABI. `puts` and `strlen` accept a string literal or a `char *`
local whose string value remains compile-time known; `read` accepts writable
`char buffer[N]` storage. Header parsing, external functions, general pointer
dereference, and multi-file compilation are not implemented yet.

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
