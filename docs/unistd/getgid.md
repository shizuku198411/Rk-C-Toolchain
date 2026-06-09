# getgid

## Name

`getgid` - return the current group id

## Synopsis

```c
#include <rkc_unistd.h>

int getgid(void);
```

## Description

Returns the numeric group id of the calling process.

## Arguments

None.

## Return Value

Returns the current group id.

## Example

```c
#include <rkc_stdio.h>
#include <rkc_unistd.h>

int main() {
  printf("gid=%d\n", getgid());
  return 0;
}
```

## Notes

The default interactive `rkc` user currently has gid `1000`; root has gid `0`.
