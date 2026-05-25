# libc-mini

`libc-mini` defines the first small programming surface usable by programs
built with Rk-C Toolchain. Until relocatable objects and `rkld` are available,
`rkcc` lowers these function calls directly to the stable Rk-C syscall ABI.

## Builtin Surface

```c
void exit(int code);
int write(int fd, const char *buf, int len);
int read(int fd, char *buf, int len);
int open(const char *path, int flags);
int close(int fd);
int puts(const char *s);
int strlen(const char *s);
int getuid(void);
int getgid(void);
```

`char buffer[N]` declares writable stack storage for `read`. `strlen` and
`puts` currently require a string literal or a `char *` local initialized from
a string literal, so their byte length remains known during compilation.

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
  return 0;
}
```

The future object/linker phase will move these builtins behind a linkable
`librkc` implementation without changing the application-facing API.
