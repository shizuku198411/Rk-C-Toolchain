## Links one or more RKO input objects into an executable RKX application.
from lib/types import U32
from user/lib/core/args import UserArgs, argAt, parseUserArgs
from user/lib/core/io import write
from user/lib/core/pathutils import PathMax, resolvePathInto
from user/lib/core/strutils import cstringEq
from user/lib/core/syscall import sysChmod, sysExit
import lib/rko_format/rko
import lib/rkx_writer/rkx_writer
import ./internal/linker


var
  parsedArgs: UserArgs
  inputPath: array[PathMax, char]
  outputPath: array[PathMax, char]
  currentObject: RkoObject
  linkState: LinkState


## Prints the command interface for the hosted object linker.
proc printUsage() =
  write("usage: rkld <input.rko> [input.rko...] -o <output.rkx>\n")


## Resolves a syscall-facing path into stable command storage.
proc storePath(input: cstring, buffer: var array[PathMax, char]): bool =
  resolvePathInto(input, buffer) != nil


## Reports one linker stage failure and exits the application.
proc fail(prefix, detail: cstring) {.noreturn.} =
  write("rkld: ")
  write(prefix)
  write(": ")
  write(detail)
  write("\n")
  sysExit(1)


## Loads RKO inputs, links final addresses, and writes an executable RKX file.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)
  if parsedArgs.argc == U32(1) and
      cstringEq(argAt(parsedArgs, U32(0)), cstring("--help")):
    printUsage()
    sysExit(0)
  if parsedArgs.argc < U32(3) or
      not cstringEq(argAt(parsedArgs, parsedArgs.argc - U32(2)), cstring("-o")):
    printUsage()
    sysExit(1)
  if not storePath(argAt(parsedArgs, parsedArgs.argc - U32(1)), outputPath):
    fail(cstring("output path"), cstring("path too long"))

  linkState.initLinkState()
  var index = U32(0)
  while index + U32(2) < parsedArgs.argc:
    if not storePath(argAt(parsedArgs, index), inputPath):
      fail(cstring("input path"), cstring("path too long"))
    let objectStatus = readRkoObject(cast[cstring](addr inputPath[0]), currentObject)
    if objectStatus != RkoOk:
      fail(cstring("object read failed"), rkoStatusText(objectStatus))
    let addStatus = linkState.addObject(currentObject)
    if addStatus != LinkOk:
      fail(cstring("link failed"), linkStatusText(addStatus))
    inc index

  var image: RkxImageInput
  let linkStatus = linkState.finishLink(image)
  if linkStatus != LinkOk:
    fail(cstring("link failed"), linkStatusText(linkStatus))
  let writerStatus = writeRkxImage(cast[cstring](addr outputPath[0]), image)
  if writerStatus != RkxWriterOk:
    fail(cstring("write failed"), rkxWriterStatusText(writerStatus))
  if sysChmod(cast[cstring](addr outputPath[0]), U32(0o755)) != 0:
    fail(cstring("chmod failed"), cstring("output not executable"))

  write("rkld: created ")
  write(cast[cstring](addr outputPath[0]))
  write("\n")
  sysExit(0)
