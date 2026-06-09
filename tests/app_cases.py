"""Smoke tests for optional Rk-C toolchain applications."""


def toolchain_tests(TestCase):
    """Returns RKX writer validation and generated executable test cases."""
    c_source_input = (
        "edit /home/rkc/src/hello.c\n"
        "int main() {\n"
        "  int n = 3;\n"
        "  int total = n * 4;\n"
        "  int bits = (6 & 3) | (1 << 3);\n"
        "  char *line = \"libc-mini write\\n\";\n"
        "  int written = write(1, line, strlen(line));\n"
        "  if (written == 16) {\n"
        "    puts(\"write from libc-mini\\n\");\n"
        "  }\n"
        "  int uid = getuid();\n"
        "  int gid = getgid();\n"
        "  if (uid == gid) {\n"
        "    puts(\"identity from libc-mini\\n\");\n"
        "  }\n"
        "  char *release = \"/etc/os-release\";\n"
        "  int fd = open(release, 1);\n"
        "  char buffer[16];\n"
        "  int got = read(fd, buffer, 12);\n"
        "  close(fd);\n"
        "  write(1, buffer, got);\n"
        "  while (n > 0) {\n"
        "    n = n - 1;\n"
        "  }\n"
        "  if (total >= 12) {\n"
        "    puts(\"compare from rkcc\\n\");\n"
        "  }\n"
        "  if ((bits ^ 10) == 0) {\n"
        "    puts(\"bits from rkcc\\n\");\n"
        "  }\n"
        "  if ((13 / 4) == 3) {\n"
        "    puts(\"divide from rkcc\\n\");\n"
        "  }\n"
        "  if ((32 >> 2) <= 8) {\n"
        "    puts(\"shift from rkcc\\n\");\n"
        "  }\n"
        "  if ((13 % 4) == 1) {\n"
        "    char *message = \"hello from rkcc!\\n\";\n"
        "    puts(message);\n"
        "  }\n"
        "  return 0;\n"
        "}\n"
        "\x18\x13\x18\x03"
    )

    hello_source_input = (
        "edit /home/rkc/src/hello.s\n"
        ".text\n"
        ".entry _start\n"
        "_start:\n"
        "  li t0, 6\n"
        "  li t1, 7\n"
        "  mul t2, t0, t1\n"
        "  li t3, 42\n"
        "  bne t2, t3, failed\n"
        "  bge t2, t3, ready\n"
        "failed:\n"
        "  li a0, 1\n"
        "  li a3, 5\n"
        "  ecall\n"
        "ready:\n"
        "  la a0, message\n"
        "  li a1, 17\n"
        "  li a3, 1\n"
        "  ecall\n"
        "  li a0, 0\n"
        "  li a3, 5\n"
        "  ecall\n"
        ".rodata\n"
        "message:\n"
        "  .asciz \"hello from rkas!\\n\"\n"
        "  .zero 4096\n"
        ".data\n"
        "seed:\n"
        "  .byte 0x2a\n"
        ".bss\n"
        "scratch:\n"
        "  .zero 16\n"
        "\x18\x13\x18\x03"
    )

    entry_object_input = (
        "edit /home/rkc/src/start.s\n"
        ".text\n"
        ".entry _start\n"
        "_start:\n"
        "  call linked_greeting\n"
        "  li a0, 0\n"
        "  li a3, 5\n"
        "  ecall\n"
        "\x18\x13\x18\x03"
    )

    greeting_object_input = (
        "edit /home/rkc/src/greeting.s\n"
        ".text\n"
        ".global linked_greeting\n"
        "linked_greeting:\n"
        "  la a0, linked_message\n"
        "  li a1, 23\n"
        "  li a3, 1\n"
        "  ecall\n"
        "  ret\n"
        ".rodata\n"
        "linked_message:\n"
        "  .asciz \"hello from linked RKO!\\n\"\n"
        "\x18\x13\x18\x03"
    )

    stdlib_source_input = (
        "edit /home/rkc/src/stdlib_hello.c\n"
        "#include <rkc_stdio.h>\n"
        "#include <rkc_stdlib.h>\n"
        "#include <rkc_string.h>\n"
        "#include <rkc_unistd.h>\n"
        "int main() {\n"
        "  char *line = \"hello from split libraries!\\n\";\n"
        "  write(1, line, strlen(line));\n"
        "  int uid = getuid();\n"
        "  int gid = getgid();\n"
        "  if (uid == gid) {\n"
        "    puts(\"identity from linked library!\\n\");\n"
        "  }\n"
        "  char *word = \"toolchain\";\n"
        "  printf(\"printf values: %d %x %s %c %%\\n\", 123, 255, word, 33);\n"
        "  char *release = \"/etc/os-release\";\n"
        "  int fd = open(release, 1);\n"
        "  char buffer[16];\n"
        "  int got = read(fd, buffer, 12);\n"
        "  close(fd);\n"
        "  write(1, buffer, got);\n"
        "  exit(0);\n"
        "}\n"
        "\x18\x13\x18\x03"
    )

    return [
        TestCase(
            "rkx writer rejects invalid layouts",
            "rkxwritecheck --self-test",
            ["rkxwritecheck: validation ok"],
        ),
        TestCase(
            "rkx writer creates executable image",
            "rkxwritecheck /home/rkc/bin/writer_hello",
            ["rkxwritecheck: created /home/rkc/bin/writer_hello"],
        ),
        TestCase(
            "inspect writer generated image",
            "rkxinfo /home/rkc/bin/writer_hello",
            [
                "magic: RKX1",
                "version: 2",
                "entry: 0x1200000",
                "capability_mask: 0x0 (none)",
                "text: va=0x1200000",
                "rodata: va=0x1201000",
                "data: va=0x1202000",
                "bss: va=0x1203000 mem=32",
                "allowed_uids: all",
            ],
        ),
        TestCase(
            "execute writer generated image",
            "/home/rkc/bin/writer_hello",
            ["hello from RKX writer"],
        ),
        TestCase(
            "remove writer generated image",
            "rm /home/rkc/bin/writer_hello",
            [],
        ),
        TestCase("rkas help", "rkas --help", ["usage: rkas"]),
        TestCase(
            "edit assembly source in user src",
            hello_source_input,
            ["[op] Exit"],
            timeout=15.0,
            append_newline=False,
        ),
        TestCase(
            "rkas assembles source into home bin",
            "rkas /home/rkc/src/hello.s -o /home/rkc/bin/hello",
            ["rkas: created /home/rkc/bin/hello"],
        ),
        TestCase(
            "inspect rkas generated image",
            "rkxinfo /home/rkc/bin/hello",
            [
                "magic: RKX1",
                "capability_mask: 0x0 (none)",
                "text: va=0x1200000",
                "rodata: va=0x1201000",
                "data: va=0x1203000",
                "bss: va=0x1204000 mem=16",
            ],
        ),
        TestCase("execute assembled image", "/home/rkc/bin/hello", regex=[r"hello from rkas!\r?\n"]),
        TestCase("remove assembled image", "rm /home/rkc/bin/hello", []),
        TestCase("remove assembly source", "rm /home/rkc/src/hello.s", []),
        TestCase("rkld help", "rkld --help", ["usage: rkld"]),
        TestCase(
            "edit linked entry object source",
            entry_object_input,
            ["[op] Exit"],
            timeout=15.0,
            append_newline=False,
        ),
        TestCase(
            "edit linked greeting object source",
            greeting_object_input,
            ["[op] Exit"],
            timeout=15.0,
            append_newline=False,
        ),
        TestCase(
            "assemble entry relocatable object",
            "rkas -c /home/rkc/src/start.s -o /home/rkc/src/a.rko",
            ["rkas: created /home/rkc/src/a.rko"],
        ),
        TestCase(
            "assemble greeting relocatable object",
            "rkas -c /home/rkc/src/greeting.s -o /home/rkc/src/b.rko",
            ["rkas: created /home/rkc/src/b.rko"],
        ),
        TestCase(
            "link cross object executable",
            "rkld /home/rkc/src/a.rko /home/rkc/src/b.rko -o /home/rkc/bin/lh",
            ["rkld: created /home/rkc/bin/lh"],
        ),
        TestCase(
            "execute cross object executable",
            "/home/rkc/bin/lh",
            regex=[r"hello from linked RKO!\r?\n"],
        ),
        TestCase("remove linked executable", "rm /home/rkc/bin/lh", []),
        TestCase("remove linked entry object", "rm /home/rkc/src/a.rko", []),
        TestCase("remove linked greeting object", "rm /home/rkc/src/b.rko", []),
        TestCase("remove linked entry source", "rm /home/rkc/src/start.s", []),
        TestCase("remove linked greeting source", "rm /home/rkc/src/greeting.s", []),
        TestCase("rkcc help", "rkcc --help", ["usage: rkcc"]),
        TestCase(
            "edit C-like source in user src",
            c_source_input,
            ["[op] Exit"],
            timeout=15.0,
            append_newline=False,
        ),
        TestCase(
            "rkcc compiles source through rkas",
            "rkcc /home/rkc/src/hello.c -o /home/rkc/bin/c_hello",
            ["rkcc: created /home/rkc/bin/c_hello"],
        ),
        TestCase(
            "inspect rkcc generated image",
            "rkxinfo /home/rkc/bin/c_hello",
            ["magic: RKX1", "capability_mask: 0x0 (none)", "text: va=0x1200000"],
        ),
        TestCase(
            "execute compiled C-like image",
            "/home/rkc/bin/c_hello",
            [
                "libc-mini write",
                "write from libc-mini",
                "identity from libc-mini",
                "NAME=\"Rk-C\"",
                "compare from rkcc",
                "bits from rkcc",
                "divide from rkcc",
                "shift from rkcc",
            ],
            regex=[r"hello from rkcc!\r?\n"],
        ),
        TestCase(
            "rkcc emits relocatable object",
            "rkcc -c /home/rkc/src/hello.c -o /home/rkc/src/c_hello.rko",
            ["rkcc: created /home/rkc/src/c_hello.rko"],
        ),
        TestCase(
            "link rkcc relocatable object",
            "rkld /home/rkc/src/c_hello.rko -o /home/rkc/bin/c_linked",
            ["rkld: created /home/rkc/bin/c_linked"],
        ),
        TestCase(
            "execute linked C-like object",
            "/home/rkc/bin/c_linked",
            ["libc-mini write", "identity from libc-mini", "hello from rkcc!"],
        ),
        TestCase("remove linked C-like image", "rm /home/rkc/bin/c_linked", []),
        TestCase("remove C-like object", "rm /home/rkc/src/c_hello.rko", []),
        TestCase("cc help", "cc --help", ["usage: cc", "cc -S", "cc -c"]),
        TestCase(
            "cc emits assembly output",
            "cc -S /home/rkc/src/hello.c -o /home/rkc/src/cc_hello.s",
            ["rkcc: created /home/rkc/src/cc_hello.s", "cc: created /home/rkc/src/cc_hello.s"],
        ),
        TestCase(
            "inspect cc assembly output",
            "cat /home/rkc/src/cc_hello.s",
            [".text", ".entry _start", "ecall"],
        ),
        TestCase("remove cc assembly output", "rm /home/rkc/src/cc_hello.s", []),
        TestCase(
            "cc emits relocatable object",
            "cc -c /home/rkc/src/hello.c -o /home/rkc/src/cc_hello.rko",
            ["rkcc: created /home/rkc/src/cc_hello.rko", "cc: created /home/rkc/src/cc_hello.rko"],
        ),
        TestCase(
            "cc links existing object input",
            "cc /home/rkc/src/cc_hello.rko -o /home/rkc/bin/cc_object",
            ["rkld: created /home/rkc/bin/cc_object", "cc: created /home/rkc/bin/cc_object"],
        ),
        TestCase(
            "execute cc object linked image",
            "/home/rkc/bin/cc_object",
            ["libc-mini write", "identity from libc-mini", "hello from rkcc!"],
        ),
        TestCase("remove cc object linked image", "rm /home/rkc/bin/cc_object", []),
        TestCase("remove cc object output", "rm /home/rkc/src/cc_hello.rko", []),
        TestCase("rkc standard library installer help", "rkcstdlib --help", ["permission denied: /bin/rkcstdlib"]),
        TestCase(
            "boot installs stdio header before login",
            "cat /usr/include/rkc_stdio.h",
            ["int puts", "int printf", "int open", "int read", "int write", "int close"],
        ),
        TestCase(
            "boot installs standard support headers before login",
            "ls -l /usr/include",
            ["rkc_stdlib.h", "rkc_string.h", "rkc_unistd.h"],
        ),
        TestCase(
            "boot installs split standard libraries before login",
            "ls -l /usr/lib",
            ["rkc_stdio.rko", "rkc_stdlib.rko", "rkc_string.rko", "rkc_unistd.rko"],
        ),
        TestCase(
            "cc compiles and links with include search option",
            "cc -I/usr/include /home/rkc/src/hello.c -o /home/rkc/bin/cc_hello",
            ["rkld: created /home/rkc/bin/cc_hello", "cc: created /home/rkc/bin/cc_hello"],
        ),
        TestCase(
            "execute cc linked C-like image",
            "/home/rkc/bin/cc_hello",
            ["libc-mini write", "identity from libc-mini", "hello from rkcc!"],
        ),
        TestCase("remove cc linked image", "rm /home/rkc/bin/cc_hello", []),
        TestCase(
            "edit standard header C-like source",
            stdlib_source_input,
            ["[op] Exit"],
            timeout=15.0,
            append_newline=False,
        ),
        TestCase(
            "cc auto-links source with installed standard headers",
            "cc /home/rkc/src/stdlib_hello.c -o /home/rkc/bin/stdlib_hello",
            ["rkld: created /home/rkc/bin/stdlib_hello", "cc: created /home/rkc/bin/stdlib_hello"],
        ),
        TestCase(
            "execute linked standard library calls",
            "/home/rkc/bin/stdlib_hello",
            [
                "hello from split libraries!",
                "identity from linked library!",
                "printf values: 123 ff toolchain ! %",
                'NAME="Rk-C"',
            ],
        ),
        TestCase("remove linked standard library image", "rm /home/rkc/bin/stdlib_hello", []),
        TestCase("remove standard header source", "rm /home/rkc/src/stdlib_hello.c", []),
        TestCase("remove compiled image", "rm /home/rkc/bin/c_hello", []),
        TestCase("remove C-like source", "rm /home/rkc/src/hello.c", []),
    ]
