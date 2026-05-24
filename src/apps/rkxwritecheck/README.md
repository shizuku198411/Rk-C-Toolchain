# rkxwritecheck

`rkxwritecheck` is a test-only validation utility for the shared RKX writer
library. It is built into application test images, but is not included in
ordinary Rk-C disk images.

It writes a small unprivileged RKX executable to a requested path and validates
that malformed image layouts are rejected.

## Usage

```text
rkxwritecheck --self-test
rkxwritecheck /home/rkc/bin/writer_hello
rkxinfo /home/rkc/bin/writer_hello
/home/rkc/bin/writer_hello
```

The generated program has separate executable, read-only, writable, and BSS
segments and prints `hello from RKX writer` before exiting. `--self-test`
checks rejection of invalid entry points, overlapping segments, and invalid
stack sizes without creating an output file.
