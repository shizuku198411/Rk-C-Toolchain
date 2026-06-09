## Drives the hosted compiler, assembler, and linker through a cc-like CLI.
from lib/types import U32, U64
from user/lib/core/args import UserArgs, argAt, parseUserArgs
from user/lib/core/io import write
from user/lib/core/pathutils import PathMax
from user/lib/core/strutils import cstringEq
from user/lib/core/syscall import SysOpenRead, sysClose, sysExec, sysExit,
  sysGetPid, sysOpen, sysReadFd, sysUnlink, sysWait


const
  RkccPath = "/bin/rkcc"
  RkldPath = "/bin/rkld"
  StandardIncludePath = "/usr/include"
  StdioLibraryPath = "/usr/lib/rkc_stdio.rko"
  StdlibLibraryPath = "/usr/lib/rkc_stdlib.rko"
  StringLibraryPath = "/usr/lib/rkc_string.rko"
  UnistdLibraryPath = "/usr/lib/rkc_unistd.rko"
  LinkInputCapacity = 8
  StandardLibraryCount = 4
  ChildArgsCapacity = PathMax * (LinkInputCapacity + 3)
  SourceScanCapacity = 1024


type
  DriverMode = enum
    DriverLink,
    DriverAssembly,
    DriverObject

  DriverOptions = object
    mode: DriverMode
    source: cstring
    output: cstring
    objects: array[LinkInputCapacity, cstring]
    objectCount: U32
    useStdlib: bool


var
  parsedArgs: UserArgs
  options: DriverOptions
  temporaryObject: array[PathMax, char]
  childArgs: array[ChildArgsCapacity, char]
  sourceScan: array[SourceScanCapacity, char]


## Prints supported compiler driver operations and the initial input policy.
proc printUsage() =
  write("usage: cc <input.c> [input.rko...] -o <output.rkx>\n")
  write("       cc -S <input.c> -o <output.s>\n")
  write("       cc -c <input.c> -o <output.rko>\n")
  write("       cc -I<dir> <input.c> [input.rko...] -o <output.rkx>\n")
  write("notes: rkc_* headers are auto-loaded from /usr/include\n")


## Reports a frontend failure and terminates the compiler driver.
proc fail(message: cstring) {.noreturn.} =
  write("cc: ")
  write(message)
  write("\n")
  sysExit(1)


## Tests whether a string begins with one option prefix.
proc startsWith(value, prefix: cstring): bool =
  var i = U32(0)
  while prefix[i] != '\0':
    if value[i] != prefix[i]:
      return false
    inc i
  true


## Tests whether a path ends with one source or object suffix.
proc endsWith(value, suffix: cstring): bool =
  var valueLen = U32(0)
  while value[valueLen] != '\0':
    inc valueLen
  var suffixLen = U32(0)
  while suffix[suffixLen] != '\0':
    inc suffixLen
  if valueLen < suffixLen:
    return false
  var i = U32(0)
  while i < suffixLen:
    if value[valueLen - suffixLen + i] != suffix[i]:
      return false
    inc i
  true


## Tests whether one public include directive begins in the source scan buffer.
proc matchesDirective(pos, size: U32, directive: cstring,
                      after: var U32): bool =
  var index = U32(0)
  while directive[index] != '\0':
    if pos + index >= size or sourceScan[pos + index] != directive[index]:
      return false
    inc index
  after = pos + index
  after >= size or sourceScan[after] == '\r' or sourceScan[after] == '\n'


## Recognizes initial public standard headers so cc can link their libraries.
proc sourceUsesStandardHeaders(path: cstring): bool =
  let fd = sysOpen(path, SysOpenRead)
  if fd < 0:
    return false

  let readLen = sysReadFd(
    fd,
    addr sourceScan[0],
    U64(SourceScanCapacity - 1),
  )
  discard sysClose(fd)
  if readLen <= 0:
    return false
  let size = U32(readLen)
  sourceScan[size] = '\0'

  var pos = U32(0)
  while true:
    while pos < size and
        (sourceScan[pos] == ' ' or sourceScan[pos] == '\t' or
         sourceScan[pos] == '\r' or sourceScan[pos] == '\n'):
      inc pos
    var after = U32(0)
    if matchesDirective(pos, size, cstring("#include <rkc_stdio.h>"), after) or
        matchesDirective(pos, size, cstring("#include <rkc_stdlib.h>"), after) or
        matchesDirective(pos, size, cstring("#include <rkc_string.h>"), after) or
        matchesDirective(pos, size, cstring("#include <rkc_unistd.h>"), after):
      return true
    return false


## Verifies that automatic standard-library linking still fits the fixed input set.
proc linkInputCapacityOk(parsed: var DriverOptions): bool =
  if parsed.mode != DriverLink:
    return true
  let compiledInput =
    if parsed.source != nil: U32(1)
    else: U32(0)
  if parsed.useStdlib:
    return parsed.objectCount + compiledInput + U32(StandardLibraryCount) <=
      U32(LinkInputCapacity)
  parsed.objectCount + compiledInput <= U32(LinkInputCapacity)


## Appends one raw child argument fragment to the command buffer.
proc appendChild(text: cstring, pos: var U32): bool =
  var i = U32(0)
  while text[i] != '\0':
    if pos + U32(1) >= U32(ChildArgsCapacity):
      return false
    childArgs[pos] = text[i]
    inc pos
    inc i
  childArgs[pos] = '\0'
  true


## Appends one space-delimited child process argument.
proc appendArgument(text: cstring, pos: var U32): bool =
  if pos > U32(0) and not appendChild(cstring(" "), pos):
    return false
  appendChild(text, pos)


## Appends one character to a temporary pathname with capacity checking.
proc appendTemporaryChar(ch: char, pos: var U32): bool =
  if pos + U32(1) >= U32(PathMax):
    return false
  temporaryObject[pos] = ch
  inc pos
  temporaryObject[pos] = '\0'
  true


## Creates a short PID-qualified temporary RKO pathname beside final output.
proc buildTemporaryPath(output: cstring): bool =
  var lastSlash = -1
  var scan = 0
  while output[scan] != '\0':
    if output[scan] == '/':
      lastSlash = scan
    inc scan

  var pos = U32(0)
  var prefixPos = 0
  while prefixPos <= lastSlash:
    if not appendTemporaryChar(output[prefixPos], pos):
      return false
    inc prefixPos

  if not appendTemporaryChar('.', pos) or not appendTemporaryChar('c', pos):
    return false
  let pid = U32(sysGetPid())
  var shift = 28
  while shift >= 0:
    let value = (pid shr U32(shift)) and U32(0xf)
    let digit =
      if value < U32(10): char(ord('0') + int(value))
      else: char(ord('a') + int(value - U32(10)))
    if not appendTemporaryChar(digit, pos):
      return false
    shift = shift - 4
  appendTemporaryChar('.', pos) and appendTemporaryChar('o', pos)


## Parses a cc-style argument vector into one constrained driver action.
proc parseOptions(args: var UserArgs, parsed: var DriverOptions): bool =
  parsed = DriverOptions(mode: DriverLink)
  var index = U32(0)
  while index < args.argc:
    let item = argAt(args, index)
    if cstringEq(item, cstring("-S")):
      if parsed.mode != DriverLink:
        return false
      parsed.mode = DriverAssembly
    elif cstringEq(item, cstring("-c")):
      if parsed.mode != DriverLink:
        return false
      parsed.mode = DriverObject
    elif cstringEq(item, cstring("-o")):
      if parsed.output != nil or index + U32(1) >= args.argc:
        return false
      inc index
      parsed.output = argAt(args, index)
    elif cstringEq(item, cstring("-I")):
      if index + U32(1) >= args.argc or
          not cstringEq(argAt(args, index + U32(1)), cstring(StandardIncludePath)):
        return false
      inc index
      parsed.useStdlib = true
    elif startsWith(item, cstring("-I")):
      if item[2] == '\0' or
          not cstringEq(cast[cstring](cast[U64](item) + U64(2)),
                        cstring(StandardIncludePath)):
        return false
      parsed.useStdlib = true
    elif item[0] == '-':
      return false
    elif endsWith(item, cstring(".c")):
      if parsed.source != nil:
        return false
      parsed.source = item
    elif endsWith(item, cstring(".rko")):
      if parsed.objectCount >= U32(LinkInputCapacity):
        return false
      parsed.objects[parsed.objectCount] = item
      inc parsed.objectCount
    else:
      return false
    inc index

  if parsed.output == nil:
    return false
  if parsed.mode == DriverAssembly or parsed.mode == DriverObject:
    return parsed.source != nil and parsed.objectCount == U32(0)
  if parsed.source != nil and parsed.objectCount >= U32(LinkInputCapacity):
    return false
  (parsed.source != nil or parsed.objectCount > U32(0)) and
    linkInputCapacityOk(parsed)


## Executes one backend command synchronously and reports success to its caller.
proc runBackend(path: cstring): bool =
  let pid = sysExec(path, cast[cstring](addr childArgs[0]), false)
  if pid < 0:
    return false
  sysWait(pid) == U64(0)


## Invokes rkcc for assembly or relocatable-object output.
proc compileOutput(mode: DriverMode, source, output: cstring): bool =
  var pos = U32(0)
  childArgs[0] = '\0'
  if options.useStdlib and
      not appendArgument(cstring("-I/usr/include"), pos):
    return false
  if mode == DriverAssembly and not appendArgument(cstring("-S"), pos):
    return false
  if mode == DriverObject and not appendArgument(cstring("-c"), pos):
    return false
  if not appendArgument(source, pos) or
      not appendArgument(cstring("-o"), pos) or
      not appendArgument(output, pos):
    return false
  runBackend(cstring(RkccPath))


## Invokes rkld over optional compiled output and caller-provided object inputs.
proc linkOutput(compiled: bool): bool =
  var pos = U32(0)
  childArgs[0] = '\0'
  if compiled and
      not appendArgument(cast[cstring](addr temporaryObject[0]), pos):
    return false
  var index = U32(0)
  while index < options.objectCount:
    if not appendArgument(options.objects[index], pos):
      return false
    inc index
  if options.useStdlib:
    if not appendArgument(cstring(StdioLibraryPath), pos) or
        not appendArgument(cstring(StdlibLibraryPath), pos) or
        not appendArgument(cstring(StringLibraryPath), pos) or
        not appendArgument(cstring(UnistdLibraryPath), pos):
      return false
  if not appendArgument(cstring("-o"), pos) or
      not appendArgument(options.output, pos):
    return false
  runBackend(cstring(RkldPath))


## Parses a build request and delegates each compilation phase to backend tools.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)
  if parsedArgs.argc == U32(1) and
      cstringEq(argAt(parsedArgs, U32(0)), cstring("--help")):
    printUsage()
    sysExit(0)
  if not parseOptions(parsedArgs, options):
    printUsage()
    sysExit(1)
  if options.source != nil and not options.useStdlib and
      sourceUsesStandardHeaders(options.source):
    options.useStdlib = true
    if not linkInputCapacityOk(options):
      fail(cstring("too many link inputs"))

  if options.mode == DriverAssembly or options.mode == DriverObject:
    if not compileOutput(options.mode, options.source, options.output):
      fail(cstring("rkcc failed"))
    write("cc: created ")
    write(options.output)
    write("\n")
    sysExit(0)

  let compileSource = options.source != nil
  if compileSource:
    if not buildTemporaryPath(options.output):
      fail(cstring("temporary object path too long"))
    if not compileOutput(
      DriverObject,
      options.source,
      cast[cstring](addr temporaryObject[0]),
    ):
      discard sysUnlink(cast[cstring](addr temporaryObject[0]))
      fail(cstring("rkcc failed"))

  let linked = linkOutput(compileSource)
  if compileSource:
    discard sysUnlink(cast[cstring](addr temporaryObject[0]))
  if not linked:
    fail(cstring("rkld failed"))

  write("cc: created ")
  write(options.output)
  write("\n")
  sysExit(0)
