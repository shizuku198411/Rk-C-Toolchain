## Assembles the hosted RISC-V source subset directly into an RKX executable.
from lib/types import U8, U32, U64
from user/lib/core/args import UserArgs, argAt, parseUserArgs
from user/lib/core/io import write
from user/lib/core/pathutils import PathMax, resolvePathInto
from user/lib/core/strutils import cstringEq
from user/lib/core/syscall import SysOpenRead, sysChmod, sysClose, sysExit,
  sysOpen, sysReadFd
import lib/rkx_writer/rkx_writer
import ./internal/assembler


const
  SourceCapacity = 16384
  ReadChunkSize = 4095


var
  parsedArgs: UserArgs
  sourcePath: array[PathMax, char]
  outputPath: array[PathMax, char]
  sourceText: array[SourceCapacity, char]


## Prints rkas command usage and the hosted assembly syntax surface.
proc printUsage() =
  write("usage: rkas <source.s> -o <output.rkx>\n")
  write("sections: .text .rodata .data .bss\n")
  write("directives: .entry .byte .asciz .zero\n")
  write("integer: add sub mul div rem and or xor slt sltu shifts\n")
  write("branch: beq bne blt bge bltu bgeu\n")


## Resolves and copies one input path into a stable syscall-facing buffer.
proc storePath(input: cstring, buffer: var array[PathMax, char]): bool =
  resolvePathInto(input, buffer) != nil


## Reads a source file through normal userspace FD APIs into the assembler buffer.
proc readSource(path: cstring, size: var U32): bool =
  let fd = sysOpen(path, SysOpenRead)
  if fd < 0:
    return false

  size = U32(0)
  while size < U32(SourceCapacity - 1):
    var requestSize = U64(SourceCapacity - 1) - U64(size)
    if requestSize > U64(ReadChunkSize):
      requestSize = U64(ReadChunkSize)
    let readLen = sysReadFd(
      fd,
      addr sourceText[size],
      requestSize,
    )
    if readLen < 0:
      discard sysClose(fd)
      return false
    if readLen == 0:
      sourceText[size] = '\0'
      discard sysClose(fd)
      return true
    size = size + U32(readLen)

  var extra: array[1, U8]
  let overflow = sysReadFd(fd, addr extra[0], U64(1)) > 0
  discard sysClose(fd)
  if overflow:
    return false

  sourceText[size] = '\0'
  true


## Prints a diagnostic describing an assembly or RKX writer failure.
proc reportFailure(prefix, detail: cstring) =
  write("rkas: ")
  write(prefix)
  write(": ")
  write(detail)
  write("\n")


## Parses command paths, assembles the source, and writes an executable RKX image.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == U32(1) and cstringEq(argAt(parsedArgs, U32(0)), cstring("--help")):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != U32(3) or
      not cstringEq(argAt(parsedArgs, U32(1)), cstring("-o")):
    printUsage()
    sysExit(1)

  if not storePath(argAt(parsedArgs, U32(0)), sourcePath) or
      not storePath(argAt(parsedArgs, U32(2)), outputPath):
    write("rkas: path too long\n")
    sysExit(1)

  var sourceSize = U32(0)
  if not readSource(cast[cstring](addr sourcePath[0]), sourceSize):
    write("rkas: failed to read source\n")
    sysExit(1)

  var image: RkxImageInput
  let assemblyStatus = assembleSource(
    cast[ptr UncheckedArray[char]](addr sourceText[0]),
    sourceSize,
    image,
  )
  if assemblyStatus != AsmOk:
    reportFailure(cstring("assemble failed"), asmStatusText(assemblyStatus))
    sysExit(1)

  let writerStatus = writeRkxImage(cast[cstring](addr outputPath[0]), image)
  if writerStatus != RkxWriterOk:
    reportFailure(cstring("write failed"), rkxWriterStatusText(writerStatus))
    sysExit(1)

  if sysChmod(cast[cstring](addr outputPath[0]), U32(0o755)) != 0:
    write("rkas: chmod failed\n")
    sysExit(1)

  write("rkas: created ")
  write(cast[cstring](addr outputPath[0]))
  write("\n")
  sysExit(0)
