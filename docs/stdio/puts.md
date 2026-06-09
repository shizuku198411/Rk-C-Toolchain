# puts

## Name

`puts` - write a NUL-terminated string to stdout

## Synopsis

```c
#include <rkc_stdio.h>

int puts(char *text);
```

## Description

Writes `text` to file descriptor `1` using the hosted standard library.
Unlike many host libc implementations, this function does not append an extra
newline; include `\n` in the string when one is needed.

## Arguments

| Name | Type | Description |
| --- | --- | --- |
| `text` | `char *` | NUL-terminated string to write |

## Return Value

Returns the number of bytes written, or a negative value if the underlying
write syscall fails.

## Example

```c
#include <rkc_stdio.h>

int main() {
  puts("hello from Rk-C\n");
  return 0;
}
```

## Notes

Without `#include <rkc_stdio.h>`, `rkcc` keeps its compatibility builtin path
for simple `puts` calls with compile-time-known string lengths.
