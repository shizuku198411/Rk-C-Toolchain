# read

## Name

`read` - read bytes from a file descriptor

## Synopsis

```c
#include <rkc_stdio.h>

int read(int fd, char *buffer, int length);
```

## Description

Reads up to `length` bytes from `fd` into `buffer`.

## Arguments

| Name | Type | Description |
| --- | --- | --- |
| `fd` | `int` | Open file descriptor |
| `buffer` | `char *` | Writable destination buffer |
| `length` | `int` | Maximum number of bytes to read |

## Return Value

Returns the number of bytes read. A return value of `0` means end of input.
Negative values report an error.

## Example

```c
#include <rkc_stdio.h>

int main() {
  char buffer[16];
  int fd = open("/etc/os-release", 1);
  int got = read(fd, buffer, 12);
  close(fd);
  write(1, buffer, got);
  return 0;
}
```

## Notes

`rkcc` currently supports stack buffers declared as `char buffer[N]` for
`read`.
