## Compiles a small C-like Rk-C source file by generating assembly for rkas.
from lib/types import U8, U32, U64
from user/lib/core/args import UserArgs, argAt, parseUserArgs
from user/lib/core/io import write
from user/lib/core/pathutils import PathMax, resolvePathInto
from user/lib/core/strutils import cstringEq
from user/lib/core/syscall import SysOpenCreate, SysOpenRead, SysOpenTrunc,
  SysOpenWrite, sysClose, sysExec, sysExit, sysOpen, sysReadFd, sysUnlink,
  sysWait, sysWriteFd
import ./internal/asm_output
import ./internal/compiler


const
  SourceCapacity = 8192
  ReadChunkSize = 4095
  GeneratedSuffix = ".rkcc.s"
  RkasPath = "/bin/rkas"
  RkasArgsCapacity = PathMax + 64


var
  parsedArgs: UserArgs
  sourcePath: array[PathMax, char]
  outputPath: array[PathMax, char]
  generatedPath: array[PathMax, char]
  sourceText: array[SourceCapacity, char]
  rkasArgs: array[RkasArgsCapacity, char]


## Prints rkcc command usage and its initially supported language surface.
proc printUsage() =
  write("usage: rkcc <source.c> -o <output.rkx>\n")
  write("supports: int main, int/char * locals, puts, exit, if/else, while, return\n")
  write("expressions: + - * / %, shifts, comparisons, &, ^, |\n")


## Resolves one requested path into a buffer stable across later path lookups.
proc storePath(input: cstring, buffer: var array[PathMax, char]): bool =
  resolvePathInto(input, buffer) != nil


## Builds the temporary assembly path beside the requested executable output.
proc buildGeneratedPath(): bool =
  var pos = U32(0)
  while outputPath[pos] != '\0':
    if pos + U32(1) >= U32(PathMax):
      return false
    generatedPath[pos] = outputPath[pos]
    inc pos
  var suffixPos = U32(0)
  while GeneratedSuffix[suffixPos] != '\0':
    if pos + U32(1) >= U32(PathMax):
      return false
    generatedPath[pos] = GeneratedSuffix[suffixPos]
    inc pos
    inc suffixPos
  generatedPath[pos] = '\0'
  true


## Reads one C-like source file into a bounded compiler input buffer.
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


## Writes generated assembly using bounded FD chunks on the output filesystem.
proc writeGeneratedAssembly(generated: var AsmOutput): bool =
  let fd = sysOpen(
    cast[cstring](addr generatedPath[0]),
    SysOpenWrite or SysOpenCreate or SysOpenTrunc,
  )
  if fd < 0:
    return false

  var offset = U32(0)
  while offset < generated.len:
    var chunk = generated.len - offset
    if chunk > U32(ReadChunkSize):
      chunk = U32(ReadChunkSize)
    if sysWriteFd(fd, addr generated.data[offset], U64(chunk)) != int32(chunk):
      discard sysClose(fd)
      return false
    offset = offset + chunk
  sysClose(fd) == 0


## Appends a C string to the child assembler argument buffer.
proc appendArgument(text: cstring, pos: var U32): bool =
  var index = U32(0)
  while text[index] != '\0':
    if pos + U32(1) >= U32(RkasArgsCapacity):
      return false
    rkasArgs[pos] = text[index]
    inc pos
    inc index
  rkasArgs[pos] = '\0'
  true


## Builds `rkas <generated> -o <output>` child arguments without allocation.
proc buildRkasArguments(): bool =
  var pos = U32(0)
  rkasArgs[0] = '\0'
  appendArgument(cast[cstring](addr generatedPath[0]), pos) and
    appendArgument(cstring(" -o "), pos) and
    appendArgument(cast[cstring](addr outputPath[0]), pos)


## Reports one compiler diagnostic and exits from the command.
proc fail(detail: cstring) {.noreturn.} =
  write("rkcc: ")
  write(detail)
  write("\n")
  sysExit(1)


## Compiles a source file, invokes rkas for RKX emission, and reports output.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == U32(1) and
      cstringEq(argAt(parsedArgs, U32(0)), cstring("--help")):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != U32(3) or
      not cstringEq(argAt(parsedArgs, U32(1)), cstring("-o")):
    printUsage()
    sysExit(1)

  if not storePath(argAt(parsedArgs, U32(0)), sourcePath) or
      not storePath(argAt(parsedArgs, U32(2)), outputPath) or
      not buildGeneratedPath():
    fail(cstring("path too long"))

  var sourceSize = U32(0)
  if not readSource(cast[cstring](addr sourcePath[0]), sourceSize):
    fail(cstring("failed to read source"))

  var generated: AsmOutput
  let compileStatus = compileSource(
    cast[ptr UncheckedArray[char]](addr sourceText[0]),
    sourceSize,
    generated,
  )
  if compileStatus != CcOk:
    write("rkcc: compile failed: ")
    write(compileStatusText(compileStatus))
    write("\n")
    sysExit(1)

  if not writeGeneratedAssembly(generated):
    discard sysUnlink(cast[cstring](addr generatedPath[0]))
    fail(cstring("failed to write generated assembly"))

  if not buildRkasArguments():
    discard sysUnlink(cast[cstring](addr generatedPath[0]))
    fail(cstring("assembler arguments too long"))

  let pid = sysExec(cstring(RkasPath), cast[cstring](addr rkasArgs[0]), false)
  if pid < 0:
    discard sysUnlink(cast[cstring](addr generatedPath[0]))
    fail(cstring("failed to start rkas"))

  let childStatus = sysWait(pid)
  discard sysUnlink(cast[cstring](addr generatedPath[0]))
  if childStatus != U64(0):
    fail(cstring("rkas failed"))

  write("rkcc: created ")
  write(cast[cstring](addr outputPath[0]))
  write("\n")
  sysExit(0)
