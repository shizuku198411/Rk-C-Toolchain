# Toolchain Documentation

Design notes, executable format decisions, language notes, and tool-facing
documentation for Rk-C Toolchain live here.

## Manual Pages

The hosted standard library manual is organized by installed public header.
Each function page follows a compact man-page style with synopsis, arguments,
return value, examples, and current toolchain notes.

| Header | Library | Functions |
| --- | --- | --- |
| `<rkc_stdio.h>` | [`stdio`](stdio/README.md) | [`puts`](stdio/puts.md), [`printf`](stdio/printf.md), [`open`](stdio/open.md), [`read`](stdio/read.md), [`write`](stdio/write.md), [`close`](stdio/close.md) |
| `<rkc_stdlib.h>` | [`stdlib`](stdlib/README.md) | [`exit`](stdlib/exit.md) |
| `<rkc_string.h>` | [`string`](string/README.md) | [`strlen`](string/strlen.md) |
| `<rkc_unistd.h>` | [`unistd`](unistd/README.md) | [`getuid`](unistd/getuid.md), [`getgid`](unistd/getgid.md) |
