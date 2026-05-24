"""Smoke tests for optional Rk-C toolchain applications."""


def toolchain_tests(TestCase):
    """Returns RKX writer validation and generated executable test cases."""
    hello_source_input = (
        "edit /home/rkc/src/hello.s\n"
        ".text\n"
        ".entry _start\n"
        "_start:\n"
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
            "resolver finds writer generated image",
            "which writer_hello",
            ["/home/rkc/bin/writer_hello"],
        ),
        TestCase(
            "execute writer generated image",
            "writer_hello",
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
                "data: va=0x1202000",
                "bss: va=0x1203000 mem=16",
            ],
        ),
        TestCase("resolver finds assembled image", "which hello", ["/home/rkc/bin/hello"]),
        TestCase("execute assembled image", "hello", regex=[r"hello from rkas!\r?\n"]),
        TestCase("remove assembled image", "rm /home/rkc/bin/hello", []),
        TestCase("remove assembly source", "rm /home/rkc/src/hello.s", []),
    ]
