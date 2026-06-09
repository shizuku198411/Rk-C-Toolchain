## Installs split public Rk-C C headers and their relocatable userspace libraries.
from lib/fixed_string import cstrlen
from lib/types import U64
from user/lib/core/args import UserArgs, argAt, parseUserArgs
from user/lib/core/io import write
from user/lib/core/strutils import cstringEq
from user/lib/core/syscall import SysFsWriteCreate, SysFsWriteOverwrite,
  sysChmod, sysExec, sysExit, sysWait, sysWriteFileMode


const
  RkasPath = "/bin/rkas"
  StdioHeaderPath = "/usr/include/rkc_stdio.h"
  StdlibHeaderPath = "/usr/include/rkc_stdlib.h"
  StringHeaderPath = "/usr/include/rkc_string.h"
  UnistdHeaderPath = "/usr/include/rkc_unistd.h"
  StdioAssemblyPath = "/usr/lib/rkc_stdio.s"
  StdlibAssemblyPath = "/usr/lib/rkc_stdlib.s"
  StringAssemblyPath = "/usr/lib/rkc_string.s"
  UnistdAssemblyPath = "/usr/lib/rkc_unistd.s"
  StdioObjectPath = "/usr/lib/rkc_stdio.rko"
  StdlibObjectPath = "/usr/lib/rkc_stdlib.rko"
  StringObjectPath = "/usr/lib/rkc_string.rko"
  UnistdObjectPath = "/usr/lib/rkc_unistd.rko"
  StdioHeaderContents =
    "int puts(char *text);\n" &
    "int printf(char *format, ...);\n" &
    "int open(char *path, int flags);\n" &
    "int read(int fd, char *buffer, int length);\n" &
    "int write(int fd, char *buffer, int length);\n" &
    "int close(int fd);\n"
  StdlibHeaderContents =
    "void exit(int status);\n"
  StringHeaderContents =
    "int strlen(char *text);\n"
  UnistdHeaderContents =
    "int getuid(void);\n" &
    "int getgid(void);\n"
  StdioAssemblyContents =
    ".text\n" &
    ".global puts\n" &
    ".global printf\n" &
    ".global open\n" &
    ".global read\n" &
    ".global write\n" &
    ".global close\n" &
    "printf:\n" &
    "  addi sp, sp, -160\n" &
    "  sd ra, 0(sp)\n" &
    "  sd s0, 8(sp)\n" &
    "  sd s1, 16(sp)\n" &
    "  sd s2, 24(sp)\n" &
    "  sd a1, 40(sp)\n" &
    "  sd a2, 48(sp)\n" &
    "  sd a3, 56(sp)\n" &
    "  sd a4, 64(sp)\n" &
    "  sd a5, 72(sp)\n" &
    "  addi s0, a0, 0\n" &
    "  addi s1, sp, 40\n" &
    "  li s2, 0\n" &
    ".Lpf_loop:\n" &
    "  lbu t0, 0(s0)\n" &
    "  beq t0, zero, .Lpf_done\n" &
    "  addi s0, s0, 1\n" &
    "  li t1, 37\n" &
    "  beq t0, t1, .Lpf_fmt\n" &
    "  call .Lpf_putc\n" &
    "  add s2, s2, a0\n" &
    "  j .Lpf_loop\n" &
    ".Lpf_fmt:\n" &
    "  lbu t0, 0(s0)\n" &
    "  beq t0, zero, .Lpf_done\n" &
    "  addi s0, s0, 1\n" &
    "  li t1, 37\n" &
    "  beq t0, t1, .Lpf_pct\n" &
    "  li t1, 115\n" &
    "  beq t0, t1, .Lpf_s\n" &
    "  li t1, 100\n" &
    "  beq t0, t1, .Lpf_d\n" &
    "  li t1, 120\n" &
    "  beq t0, t1, .Lpf_x\n" &
    "  li t1, 99\n" &
    "  beq t0, t1, .Lpf_c\n" &
    "  li t0, 37\n" &
    "  call .Lpf_putc\n" &
    "  add s2, s2, a0\n" &
    "  j .Lpf_loop\n" &
    ".Lpf_pct:\n" &
    "  li t0, 37\n" &
    "  call .Lpf_putc\n" &
    "  add s2, s2, a0\n" &
    "  j .Lpf_loop\n" &
    ".Lpf_s:\n" &
    "  ld a0, 0(s1)\n" &
    "  addi s1, s1, 8\n" &
    "  call .Lpf_puts\n" &
    "  add s2, s2, a0\n" &
    "  j .Lpf_loop\n" &
    ".Lpf_d:\n" &
    "  ld a0, 0(s1)\n" &
    "  addi s1, s1, 8\n" &
    "  call .Lpf_dec\n" &
    "  add s2, s2, a0\n" &
    "  j .Lpf_loop\n" &
    ".Lpf_x:\n" &
    "  ld a0, 0(s1)\n" &
    "  addi s1, s1, 8\n" &
    "  call .Lpf_hex\n" &
    "  add s2, s2, a0\n" &
    "  j .Lpf_loop\n" &
    ".Lpf_c:\n" &
    "  ld t0, 0(s1)\n" &
    "  addi s1, s1, 8\n" &
    "  call .Lpf_putc\n" &
    "  add s2, s2, a0\n" &
    "  j .Lpf_loop\n" &
    ".Lpf_done:\n" &
    "  addi a0, s2, 0\n" &
    "  ld ra, 0(sp)\n" &
    "  ld s0, 8(sp)\n" &
    "  ld s1, 16(sp)\n" &
    "  ld s2, 24(sp)\n" &
    "  addi sp, sp, 160\n" &
    "  ret\n" &
    ".Lpf_putc:\n" &
    "  sb t0, 96(sp)\n" &
    "  li a0, 1\n" &
    "  addi a1, sp, 96\n" &
    "  li a2, 1\n" &
    "  li a3, 59\n" &
    "  ecall\n" &
    "  ret\n" &
    ".Lpf_puts:\n" &
    "  beq a0, zero, .Lpf_puts_zero\n" &
    "  addi t0, a0, 0\n" &
    "  li t1, 0\n" &
    ".Lpf_puts_len:\n" &
    "  lbu t2, 0(t0)\n" &
    "  beq t2, zero, .Lpf_puts_write\n" &
    "  addi t0, t0, 1\n" &
    "  addi t1, t1, 1\n" &
    "  j .Lpf_puts_len\n" &
    ".Lpf_puts_write:\n" &
    "  addi a1, a0, 0\n" &
    "  li a0, 1\n" &
    "  addi a2, t1, 0\n" &
    "  li a3, 59\n" &
    "  ecall\n" &
    "  ret\n" &
    ".Lpf_puts_zero:\n" &
    "  li a0, 0\n" &
    "  ret\n" &
    ".Lpf_dec:\n" &
    "  addi t0, a0, 0\n" &
    "  addi t3, sp, 127\n" &
    "  li t4, 0\n" &
    "  li t5, 0\n" &
    "  bge t0, zero, .Lpf_dec_abs\n" &
    "  li t5, 1\n" &
    "  sub t0, zero, t0\n" &
    ".Lpf_dec_abs:\n" &
    "  li t1, 10\n" &
    "  bne t0, zero, .Lpf_dec_loop\n" &
    "  li t2, 48\n" &
    "  sb t2, 0(t3)\n" &
    "  addi t3, t3, -1\n" &
    "  addi t4, t4, 1\n" &
    "  j .Lpf_dec_sign\n" &
    ".Lpf_dec_loop:\n" &
    "  rem t2, t0, t1\n" &
    "  div t0, t0, t1\n" &
    "  addi t2, t2, 48\n" &
    "  sb t2, 0(t3)\n" &
    "  addi t3, t3, -1\n" &
    "  addi t4, t4, 1\n" &
    "  bne t0, zero, .Lpf_dec_loop\n" &
    ".Lpf_dec_sign:\n" &
    "  beq t5, zero, .Lpf_dec_write\n" &
    "  li t2, 45\n" &
    "  sb t2, 0(t3)\n" &
    "  addi t3, t3, -1\n" &
    "  addi t4, t4, 1\n" &
    ".Lpf_dec_write:\n" &
    "  addi a1, t3, 1\n" &
    "  li a0, 1\n" &
    "  addi a2, t4, 0\n" &
    "  li a3, 59\n" &
    "  ecall\n" &
    "  ret\n" &
    ".Lpf_hex:\n" &
    "  addi t0, a0, 0\n" &
    "  addi t3, sp, 96\n" &
    "  li t4, 0\n" &
    "  li t5, 0\n" &
    "  li t1, 60\n" &
    ".Lpf_hex_loop:\n" &
    "  srl t2, t0, t1\n" &
    "  andi t2, t2, 15\n" &
    "  bne t2, zero, .Lpf_hex_emit\n" &
    "  bne t5, zero, .Lpf_hex_emit\n" &
    "  bne t1, zero, .Lpf_hex_next\n" &
    ".Lpf_hex_emit:\n" &
    "  li t5, 1\n" &
    "  li t6, 10\n" &
    "  blt t2, t6, .Lpf_hex_digit\n" &
    "  addi t2, t2, 87\n" &
    "  j .Lpf_hex_store\n" &
    ".Lpf_hex_digit:\n" &
    "  addi t2, t2, 48\n" &
    ".Lpf_hex_store:\n" &
    "  sb t2, 0(t3)\n" &
    "  addi t3, t3, 1\n" &
    "  addi t4, t4, 1\n" &
    ".Lpf_hex_next:\n" &
    "  beq t1, zero, .Lpf_hex_write\n" &
    "  addi t1, t1, -4\n" &
    "  j .Lpf_hex_loop\n" &
    ".Lpf_hex_write:\n" &
    "  li a0, 1\n" &
    "  addi a1, sp, 96\n" &
    "  addi a2, t4, 0\n" &
    "  li a3, 59\n" &
    "  ecall\n" &
    "  ret\n" &
    "puts:\n" &
    "  addi sp, sp, -16\n" &
    "  sd ra, 0(sp)\n" &
    "  sd a0, 8(sp)\n" &
    "  call strlen\n" &
    "  addi a2, a0, 0\n" &
    "  ld a1, 8(sp)\n" &
    "  li a0, 1\n" &
    "  call write\n" &
    "  ld ra, 0(sp)\n" &
    "  addi sp, sp, 16\n" &
    "  ret\n" &
    "open:\n" &
    "  li a3, 57\n" &
    "  ecall\n" &
    "  ret\n" &
    "read:\n" &
    "  li a3, 58\n" &
    "  ecall\n" &
    "  ret\n" &
    "write:\n" &
    "  li a3, 59\n" &
    "  ecall\n" &
    "  ret\n" &
    "close:\n" &
    "  li a3, 60\n" &
    "  ecall\n" &
    "  ret\n" &
    ".rodata\n" &
    ".data\n" &
    ".bss\n"
  StdlibAssemblyContents =
    ".text\n" &
    ".global exit\n" &
    "exit:\n" &
    "  li a3, 5\n" &
    "  ecall\n" &
    "  j exit\n" &
    ".rodata\n" &
    ".data\n" &
    ".bss\n"
  StringAssemblyContents =
    ".text\n" &
    ".global strlen\n" &
    "strlen:\n" &
    "  addi t0, a0, 0\n" &
    "  li a0, 0\n" &
    ".Lstrlen_loop:\n" &
    "  lbu t1, 0(t0)\n" &
    "  beq t1, zero, .Lstrlen_done\n" &
    "  addi t0, t0, 1\n" &
    "  addi a0, a0, 1\n" &
    "  j .Lstrlen_loop\n" &
    ".Lstrlen_done:\n" &
    "  ret\n" &
    ".rodata\n" &
    ".data\n" &
    ".bss\n"
  UnistdAssemblyContents =
    ".text\n" &
    ".global getuid\n" &
    ".global getgid\n" &
    "getuid:\n" &
    "  li a3, 76\n" &
    "  ecall\n" &
    "  ret\n" &
    "getgid:\n" &
    "  li a3, 77\n" &
    "  ecall\n" &
    "  ret\n" &
    ".rodata\n" &
    ".data\n" &
    ".bss\n"
  StdioRkasArguments = "-c /usr/lib/rkc_stdio.s -o /usr/lib/rkc_stdio.rko"
  StdlibRkasArguments = "-c /usr/lib/rkc_stdlib.s -o /usr/lib/rkc_stdlib.rko"
  StringRkasArguments = "-c /usr/lib/rkc_string.s -o /usr/lib/rkc_string.rko"
  UnistdRkasArguments = "-c /usr/lib/rkc_unistd.s -o /usr/lib/rkc_unistd.rko"


var parsedArgs: UserArgs


## Prints the standard library installation command usage.
proc printUsage() =
  write("usage: rkcstdlib --install\n")


## Writes one installed standard-library source artifact with root ownership.
proc writeInstalledFile(path, content: cstring): bool =
  sysWriteFileMode(
    path,
    cast[pointer](content),
    cstrlen(content),
    SysFsWriteCreate or SysFsWriteOverwrite,
  ) == 0 and sysChmod(path, 0o644) == 0


## Assembles one installed library source and protects its public object output.
proc assembleLibrary(arguments, objectPath: cstring): bool =
  let pid = sysExec(cstring(RkasPath), arguments, false)
  if pid < 0 or sysWait(pid) != U64(0):
    return false
  sysChmod(objectPath, 0o644) == 0


## Installs split headers and assembles their linkable library objects.
proc installLibrary(): bool =
  if not writeInstalledFile(cstring(StdioHeaderPath), cstring(StdioHeaderContents)) or
      not writeInstalledFile(cstring(StdlibHeaderPath), cstring(StdlibHeaderContents)) or
      not writeInstalledFile(cstring(StringHeaderPath), cstring(StringHeaderContents)) or
      not writeInstalledFile(cstring(UnistdHeaderPath), cstring(UnistdHeaderContents)):
    write("rkcstdlib: failed to write public headers\n")
    return false

  if not writeInstalledFile(cstring(StdioAssemblyPath), cstring(StdioAssemblyContents)) or
      not writeInstalledFile(cstring(StdlibAssemblyPath), cstring(StdlibAssemblyContents)) or
      not writeInstalledFile(cstring(StringAssemblyPath), cstring(StringAssemblyContents)) or
      not writeInstalledFile(cstring(UnistdAssemblyPath), cstring(UnistdAssemblyContents)):
    write("rkcstdlib: failed to write library assembly\n")
    return false

  if not assembleLibrary(cstring(StdioRkasArguments), cstring(StdioObjectPath)) or
      not assembleLibrary(cstring(StdlibRkasArguments), cstring(StdlibObjectPath)) or
      not assembleLibrary(cstring(StringRkasArguments), cstring(StringObjectPath)) or
      not assembleLibrary(cstring(UnistdRkasArguments), cstring(UnistdObjectPath)):
    write("rkcstdlib: failed to assemble public libraries\n")
    return false

  write("rkcstdlib: installed /usr/include/rkc_stdio.h\n")
  write("rkcstdlib: installed /usr/include/rkc_stdlib.h\n")
  write("rkcstdlib: installed /usr/include/rkc_string.h\n")
  write("rkcstdlib: installed /usr/include/rkc_unistd.h\n")
  write("rkcstdlib: installed /usr/lib/rkc_stdio.rko\n")
  write("rkcstdlib: installed /usr/lib/rkc_stdlib.rko\n")
  write("rkcstdlib: installed /usr/lib/rkc_string.rko\n")
  write("rkcstdlib: installed /usr/lib/rkc_unistd.rko\n")
  true


## Dispatches root-owned standard library installation from userspace.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)
  if parsedArgs.argc == 1 and
      cstringEq(argAt(parsedArgs, 0), cstring("--help")):
    printUsage()
    sysExit(0)
  if parsedArgs.argc != 1 or
      not cstringEq(argAt(parsedArgs, 0), cstring("--install")):
    printUsage()
    sysExit(1)
  if not installLibrary():
    sysExit(1)
  sysExit(0)
