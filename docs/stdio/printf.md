# printf

## Name

`printf` - format a small set of values to stdout

## Synopsis

```c
#include <rkc_stdio.h>

int printf(char *format, ...);
```

## Description

Formats values into stdout. The current hosted implementation supports a small
development-friendly subset:

| Specifier | Output |
| --- | --- |
| `%s` | NUL-terminated string |
| `%d` | Signed decimal integer |
| `%x` | Lowercase hexadecimal integer without a `0x` prefix |
| `%c` | One character from an integer value |
| `%%` | Literal percent sign |

## Arguments

| Name | Type | Description |
| --- | --- | --- |
| `format` | `char *` | NUL-terminated format string |
| `...` | values | Up to five values after `format` |

## Return Value

Returns the total number of bytes written by the formatter.

## Example

```c
#include <rkc_stdio.h>

int main() {
  char *name = "toolchain";
  printf("value=%d hex=%x name=%s mark=%c %%\n", 123, 255, name, 33);
  return 0;
}
```

Expected output:

```text
value=123 hex=ff name=toolchain mark=! %
```

## Notes

`printf` is available through the linked standard library path. It is not
lowered by the compatibility builtin path used for sources without `rkc_*`
headers.
