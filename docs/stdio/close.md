# close

## Name

`close` - close an open file descriptor

## Synopsis

```c
#include <rkc_stdio.h>

int close(int fd);
```

## Description

Closes `fd` and releases the descriptor in the calling process.

## Arguments

| Name | Type | Description |
| --- | --- | --- |
| `fd` | `int` | File descriptor to close |

## Return Value

Returns `0` on success, or a negative value on failure.

## Example

```c
#include <rkc_stdio.h>

int main() {
  int fd = open("/etc/os-release", 1);
  if (fd >= 0) {
    close(fd);
  }
  return 0;
}
```

## Notes

Close file descriptors when a program no longer needs them, especially before
long-running loops or process handoff.
