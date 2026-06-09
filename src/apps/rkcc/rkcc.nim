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
  StdioHeaderPath = "/usr/include/rkc_stdio.h"
  StdlibHeaderPath = "/usr/include/rkc_stdlib.h"
  StringHeaderPath = "/usr/include/rkc_string.h"
  UnistdHeaderPath = "/usr/include/rkc_unistd.h"
  StandardIncludePath = "/usr/include"


type
  HeaderUsage = object
    stdio: bool
    stdlib: bool
    stringLib: bool
    unistd: bool


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
  write("       rkcc -S <source.c> -o <output.s>\n")
  write("       rkcc -c <source.c> -o <output.rko>\n")
  write("       rkcc -I/usr/include -c <source.c> -o <output.rko>\n")
  write("supports: int main, int/char * locals, puts, printf, exit, if/else, while, return\n")
  write("expressions: + - * / %, shifts, comparisons, &, ^, |\n")
  write("headers: rkc_* headers are auto-loaded from /usr/include\n")


## Resolves one requested path into a buffer stable across later path lookups.
proc storePath(input: cstring, buffer: var array[PathMax, char]): bool =
  resolvePathInto(input, buffer) != nil


## Tests whether a command option starts with one fixed prefix.
proc startsWith(value, prefix: cstring): bool =
  var i = U32(0)
  while prefix[i] != '\0':
    if value[i] != prefix[i]:
      return false
    inc i
  true


## Tests whether one public include directive begins at the requested offset.
proc matchesDirective(pos, size: U32, directive: cstring,
                      after: var U32): bool =
  var index = U32(0)
  while directive[index] != '\0':
    if pos + index >= size or sourceText[pos + index] != directive[index]:
      return false
    inc index
  after = pos + index
  after >= size or sourceText[after] == '\r' or sourceText[after] == '\n'


## Recognizes all initial public headers and returns the translation-unit body.
proc findStandardHeaders(size: U32, bodyOffset: var U32,
                         usage: var HeaderUsage): bool =
  var pos = U32(0)
  var included = false
  while true:
    while pos < size and
        (sourceText[pos] == ' ' or sourceText[pos] == '\t' or
         sourceText[pos] == '\r' or sourceText[pos] == '\n'):
      inc pos
    var after = U32(0)
    if matchesDirective(pos, size, cstring("#include <rkc_stdio.h>"), after):
      usage.stdio = true
    elif matchesDirective(pos, size, cstring("#include <rkc_stdlib.h>"), after):
      usage.stdlib = true
    elif matchesDirective(pos, size, cstring("#include <rkc_string.h>"), after):
      usage.stringLib = true
    elif matchesDirective(pos, size, cstring("#include <rkc_unistd.h>"), after):
      usage.unistd = true
    else:
      break
    included = true
    pos = after
  if included:
    bodyOffset = pos
  included


## Checks that one public header selected by -I is installed.
proc installedHeader(path: cstring): bool =
  let fd = sysOpen(path, SysOpenRead)
  if fd < 0:
    return false
  sysClose(fd) == 0


## Checks that every included public standard header is installed.
proc standardHeadersAvailable(usage: HeaderUsage): bool =
  (not usage.stdio or installedHeader(cstring(StdioHeaderPath))) and
    (not usage.stdlib or installedHeader(cstring(StdlibHeaderPath))) and
    (not usage.stringLib or installedHeader(cstring(StringHeaderPath))) and
    (not usage.unistd or installedHeader(cstring(UnistdHeaderPath)))


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


## Writes generated assembly to one output path using bounded FD chunks.
proc writeGeneratedAssembly(path: cstring, generated: var AsmOutput): bool =
  let fd = sysOpen(
    path,
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


## Builds child assembler arguments for executable or relocatable output.
proc buildRkasArguments(compileOnly: bool): bool =
  var pos = U32(0)
  rkasArgs[0] = '\0'
  if compileOnly and not appendArgument(cstring("-c "), pos):
    return false
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

  var base = U32(0)
  if startsWith(argAt(parsedArgs, U32(0)), cstring("-I")):
    let option = argAt(parsedArgs, U32(0))
    if option[2] != '\0':
      if not cstringEq(cast[cstring](cast[U64](option) + U64(2)),
                       cstring(StandardIncludePath)):
        fail(cstring("only /usr/include is currently supported"))
      base = U32(1)
    elif parsedArgs.argc > U32(1) and
        cstringEq(argAt(parsedArgs, U32(1)), cstring(StandardIncludePath)):
      base = U32(2)
    else:
      fail(cstring("only /usr/include is currently supported"))

  let remaining = parsedArgs.argc - base
  let assemblyOnly = remaining == U32(4) and
    cstringEq(argAt(parsedArgs, base), cstring("-S")) and
    cstringEq(argAt(parsedArgs, base + U32(2)), cstring("-o"))
  let compileOnly = remaining == U32(4) and
    cstringEq(argAt(parsedArgs, base), cstring("-c")) and
    cstringEq(argAt(parsedArgs, base + U32(2)), cstring("-o"))
  let executable = remaining == U32(3) and
    cstringEq(argAt(parsedArgs, base + U32(1)), cstring("-o"))
  if not assemblyOnly and not compileOnly and not executable:
    printUsage()
    sysExit(1)

  let sourceArg =
    if assemblyOnly or compileOnly: argAt(parsedArgs, base + U32(1))
    else: argAt(parsedArgs, base)
  let outputArg =
    if assemblyOnly or compileOnly: argAt(parsedArgs, base + U32(3))
    else: argAt(parsedArgs, base + U32(2))
  if not storePath(sourceArg, sourcePath) or
      not storePath(outputArg, outputPath):
    fail(cstring("path too long"))

  var sourceSize = U32(0)
  if not readSource(cast[cstring](addr sourcePath[0]), sourceSize):
    fail(cstring("failed to read source"))

  var bodyOffset = U32(0)
  var headerUsage: HeaderUsage
  let useStdlib = findStandardHeaders(sourceSize, bodyOffset, headerUsage)
  if useStdlib and not standardHeadersAvailable(headerUsage):
    fail(cstring("rkc_* headers require installed /usr/include files"))
  if not useStdlib:
    bodyOffset = U32(0)

  var generated: AsmOutput
  let compileStatus = compileSource(
    cast[ptr UncheckedArray[char]](
      cast[U64](addr sourceText[0]) + U64(bodyOffset)),
    sourceSize - bodyOffset,
    generated,
    useStdlib,
  )
  if compileStatus != CcOk:
    write("rkcc: compile failed: ")
    write(compileStatusText(compileStatus))
    write("\n")
    sysExit(1)

  if assemblyOnly:
    if not writeGeneratedAssembly(cast[cstring](addr outputPath[0]), generated):
      fail(cstring("failed to write generated assembly"))
    write("rkcc: created ")
    write(cast[cstring](addr outputPath[0]))
    write("\n")
    sysExit(0)

  if not buildGeneratedPath():
    fail(cstring("path too long"))
  if not writeGeneratedAssembly(cast[cstring](addr generatedPath[0]), generated):
    discard sysUnlink(cast[cstring](addr generatedPath[0]))
    fail(cstring("failed to write generated assembly"))

  if not buildRkasArguments(compileOnly):
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
