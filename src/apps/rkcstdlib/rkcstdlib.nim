## Installs the public Rk-C C header and builds its relocatable standard library.
from lib/fixed_string import cstrlen
from lib/types import U64
from user/lib/core/args import UserArgs, argAt, parseUserArgs
from user/lib/core/io import write
from user/lib/core/strutils import cstringEq
from user/lib/core/syscall import SysFsWriteCreate, SysFsWriteOverwrite,
  sysChmod, sysExec, sysExit, sysWait, sysWriteFileMode


const
  HeaderPath = "/usr/include/rkc.h"
  AssemblyPath = "/usr/lib/librkc.s"
  ObjectPath = "/usr/lib/librkc.rko"
  RkasPath = "/bin/rkas"
  HeaderContents =
    "int puts(char *text);\n" &
    "int strlen(char *text);\n" &
    "int write(int fd, char *buffer, int length);\n" &
    "void exit(int status);\n"
  AssemblyContents =
    ".text\n" &
    ".global puts\n" &
    ".global strlen\n" &
    ".global write\n" &
    ".global exit\n" &
    "puts:\n" &
    "  addi sp, sp, -16\n" &
    "  sd ra, 0(sp)\n" &
    "  sd a0, 8(sp)\n" &
    "  call strlen\n" &
    "  addi a2, a0, 0\n" &
    "  ld a1, 8(sp)\n" &
    "  li a0, 1\n" &
    "  li a3, 59\n" &
    "  ecall\n" &
    "  ld ra, 0(sp)\n" &
    "  addi sp, sp, 16\n" &
    "  ret\n" &
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
    "write:\n" &
    "  li a3, 59\n" &
    "  ecall\n" &
    "  ret\n" &
    "exit:\n" &
    "  li a3, 5\n" &
    "  ecall\n" &
    "  j exit\n" &
    ".rodata\n" &
    ".data\n" &
    ".bss\n"
  RkasArguments = "-c /usr/lib/librkc.s -o /usr/lib/librkc.rko"


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


## Installs the header and assembles the linkable standard-library object.
proc installLibrary(): bool =
  if not writeInstalledFile(cstring(HeaderPath), cstring(HeaderContents)):
    write("rkcstdlib: failed to write /usr/include/rkc.h\n")
    return false
  if not writeInstalledFile(cstring(AssemblyPath), cstring(AssemblyContents)):
    write("rkcstdlib: failed to write /usr/lib/librkc.s\n")
    return false

  let pid = sysExec(cstring(RkasPath), cstring(RkasArguments), false)
  if pid < 0 or sysWait(pid) != U64(0):
    write("rkcstdlib: failed to assemble /usr/lib/librkc.rko\n")
    return false
  if sysChmod(cstring(ObjectPath), 0o644) != 0:
    write("rkcstdlib: failed to protect /usr/lib/librkc.rko\n")
    return false

  write("rkcstdlib: installed /usr/include/rkc.h\n")
  write("rkcstdlib: installed /usr/lib/librkc.rko\n")
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
