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
        TestCase("remove compiled image", "rm /home/rkc/bin/c_hello", []),
        TestCase("remove C-like source", "rm /home/rkc/src/hello.c", []),
    ]
