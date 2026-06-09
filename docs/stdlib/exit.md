# exit

## Name

`exit` - terminate the current process

## Synopsis

```c
#include <rkc_stdlib.h>

void exit(int status);
```

## Description

Terminates the current process and reports `status` to the parent process.
`exit` does not return.

## Arguments

| Name | Type | Description |
| --- | --- | --- |
| `status` | `int` | Process exit status |

## Return Value

This function does not return.

## Example

```c
#include <rkc_stdlib.h>

int main() {
  exit(0);
}
```

## Notes

Returning from `main` is also supported by `rkcc`; use `exit` when a program
needs to terminate from a nested control path.
