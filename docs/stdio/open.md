# open

## Name

`open` - open a filesystem path

## Synopsis

```c
#include <rkc_stdio.h>

int open(char *path, int flags);
```

## Description

Opens `path` with the requested Rk-C filesystem flags and returns a file
descriptor.

## Arguments

| Name | Type | Description |
| --- | --- | --- |
| `path` | `char *` | NUL-terminated filesystem path |
| `flags` | `int` | Rk-C open flag bitmask |

## Return Value

Returns a non-negative file descriptor on success, or a negative value on
failure.

## Example

```c
#include <rkc_stdio.h>

int main() {
  int fd = open("/etc/os-release", 1);
  if (fd < 0) {
    return 1;
  }
  close(fd);
  return 0;
}
```

## Notes

The common read-only flag value used by current examples is `1`.
