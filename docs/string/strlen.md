# strlen

## Name

`strlen` - count bytes in a NUL-terminated string

## Synopsis

```c
#include <rkc_string.h>

int strlen(char *text);
```

## Description

Counts bytes in `text` until the first `\0` byte.

## Arguments

| Name | Type | Description |
| --- | --- | --- |
| `text` | `char *` | NUL-terminated string |

## Return Value

Returns the number of bytes before the first NUL byte.

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

Without `#include <rkc_string.h>`, `rkcc` can still lower simple `strlen`
calls for string literals and `char *` locals whose length is known at compile
time.
