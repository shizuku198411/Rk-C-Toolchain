# RKX Writer

`rkx_writer.nim` is the shared RKX executable emission library for Rk-C
Toolchain.

It accepts already classified text, read-only data, writable data, and BSS
segments from toolchain applications. It validates the resulting layout
against loader-facing constraints and emits an RKX image without requested
privileged capabilities or UID restrictions.

`rkas` uses this library for assembled programs. The test-only
`rkxwritecheck` utility generates a small image and exercises invalid layouts
as integration coverage.
