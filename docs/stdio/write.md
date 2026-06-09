# write

## Name

`write` - write bytes to a file descriptor

## Synopsis

```c
#include <rkc_stdio.h>

int write(int fd, char *buffer, int length);
```

## Description

Writes `length` bytes from `buffer` to `fd`.

## Arguments

| Name | Type | Description |
| --- | --- | --- |
| `fd` | `int` | Destination file descriptor |
| `buffer` | `char *` | Source byte buffer |
| `length` | `int` | Number of bytes to write |

## Return Value

Returns the number of bytes written, or a negative value on failure.

## Example

```c
#include <rkc_stdio.h>
#include <rkc_string.h>

int main() {
  char *message = "hello\n";
  write(1, message, strlen(message));
  return 0;
}
```

## Notes

File descriptor `1` is stdout in the hosted shell environment.
