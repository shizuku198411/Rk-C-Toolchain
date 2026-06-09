# getuid

## Name

`getuid` - return the current user id

## Synopsis

```c
#include <rkc_unistd.h>

int getuid(void);
```

## Description

Returns the numeric user id of the calling process.

## Arguments

None.

## Return Value

Returns the current user id.

## Example

```c
#include <rkc_stdio.h>
#include <rkc_unistd.h>

int main() {
  printf("uid=%d\n", getuid());
  return 0;
}
```

## Notes

The default interactive `rkc` user currently has uid `1000`; root has uid `0`.
