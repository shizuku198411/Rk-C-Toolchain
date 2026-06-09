# libc-mini

`libc-mini` defines the first small programming surface usable by programs
built with Rk-C Toolchain. Calls can either be lowered directly by `rkcc` for
the early builtin path or resolved from the split standard library objects
installed under `/usr/lib`.

## Builtin Surface

```c
void exit(int code);
int write(int fd, const char *buf, int len);
int read(int fd, char *buf, int len);
int open(const char *path, int flags);
int close(int fd);
int puts(const char *s);
int printf(const char *fmt, ...);
int strlen(const char *s);
int getuid(void);
int getgid(void);
```

`char buffer[N]` declares writable stack storage for `read`. `strlen` and
`puts` currently require a string literal or a `char *` local initialized from
a string literal, so their byte length remains known during compilation.
`printf` is available through the linked standard library path and currently
supports `%s`, `%d`, `%x`, `%c`, and `%%` with up to five value arguments.
See the hosted standard library manual under [`docs/`](../../../docs/README.md)
for per-header and per-function pages.

## Example

```c
int main() {
  char *message = "hello from libc-mini\n";
  int written = write(1, message, strlen(message));
  char buffer[16];
  int fd = open("/etc/os-release", 1);
  int count = read(fd, buffer, 12);
  close(fd);
  write(1, buffer, count);
  printf("read %d bytes from %s\n", count, "/etc/os-release");
  return 0;
}
```
