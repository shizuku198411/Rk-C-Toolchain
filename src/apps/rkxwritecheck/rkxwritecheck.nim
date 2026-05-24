## Generates a small executable RKX image to validate the toolchain writer path.
from lib/types import U8, U32, U64
from user/lib/core/args import UserArgs, argAt, parseUserArgs
from user/lib/core/io import write
from user/lib/core/pathutils import resolvePath
from user/lib/core/strutils import cstringEq
from user/lib/core/syscall import sysChmod, sysExit
import lib/rkx_writer/rkx_writer


const
  GeneratedTextVa = RkxWriterUserBase
  GeneratedRodataVa = RkxWriterUserBase + U64(0x1000)
  GeneratedDataVa = RkxWriterUserBase + U64(0x2000)
  GeneratedBssVa = RkxWriterUserBase + U64(0x3000)
  GeneratedMessage = cstring("hello from RKX writer\n")
  GeneratedMessageLen = U64(22)
  TextSize = 32
  RodataSize = 22
  DataSize = 1
  GeneratedBssSize = U64(32)


var
  parsedArgs: UserArgs
  textBytes: array[TextSize, U8]
  rodataBytes: array[RodataSize, U8]
  dataBytes: array[DataSize, U8]


## Prints rkxwritecheck usage information.
proc printUsage() =
  write("usage: rkxwritecheck <output.rkx>\n")
  write("       rkxwritecheck --self-test\n")


## Places a little-endian RISC-V instruction into the generated text section.
proc putInstruction(offset: int, instruction: U32) =
  textBytes[offset] = U8(instruction and U32(0xff))
  textBytes[offset + 1] = U8((instruction shr U32(8)) and U32(0xff))
  textBytes[offset + 2] = U8((instruction shr U32(16)) and U32(0xff))
  textBytes[offset + 3] = U8((instruction shr U32(24)) and U32(0xff))


## Encodes an ADDI instruction used by the generated validation application.
proc addi(rd, rs1, immediate: U32): U32 =
  ((immediate and U32(0xfff)) shl U32(20)) or
    ((rs1 and U32(0x1f)) shl U32(15)) or
    ((rd and U32(0x1f)) shl U32(7)) or
    U32(0x13)


## Encodes a LUI instruction used to materialize the generated message address.
proc lui(rd, immediate: U32): U32 =
  ((immediate and U32(0xfffff)) shl U32(12)) or
    ((rd and U32(0x1f)) shl U32(7)) or
    U32(0x37)


## Builds code that writes a read-only string and then exits successfully.
proc buildGeneratedText() =
  # a0 = message pointer; a1 = length; a3 = SysWrite.
  putInstruction(0, lui(U32(10), U32(GeneratedRodataVa shr U64(12))))
  putInstruction(4, addi(U32(11), U32(0), U32(GeneratedMessageLen)))
  putInstruction(8, addi(U32(13), U32(0), U32(1)))
  putInstruction(12, U32(0x00000073)) # ecall

  # a0 = success; a3 = SysExit.
  putInstruction(16, addi(U32(10), U32(0), U32(0)))
  putInstruction(20, addi(U32(13), U32(0), U32(5)))
  putInstruction(24, U32(0x00000073)) # ecall
  putInstruction(28, U32(0x0000006f)) # spin if exit unexpectedly returns


## Copies the generated greeting into the read-only data section.
proc buildGeneratedRodata() =
  var i = 0
  while i < RodataSize:
    rodataBytes[i] = U8(ord(GeneratedMessage[i]))
    inc i


## Builds all byte sections used by the generated validation application.
proc buildGeneratedSections() =
  buildGeneratedText()
  buildGeneratedRodata()
  dataBytes[0] = U8(0x5a)


## Returns the valid generated image descriptor supplied to the writer.
proc generatedImage(): RkxImageInput =
  RkxImageInput(
    entryVa: GeneratedTextVa,
    text: RkxSegmentInput(
      va: GeneratedTextVa,
      data: addr textBytes[0],
      fileSize: U64(TextSize),
      memSize: U64(TextSize),
    ),
    rodata: RkxSegmentInput(
      va: GeneratedRodataVa,
      data: addr rodataBytes[0],
      fileSize: U64(RodataSize),
      memSize: U64(RodataSize),
    ),
    data: RkxSegmentInput(
      va: GeneratedDataVa,
      data: addr dataBytes[0],
      fileSize: U64(DataSize),
      memSize: U64(DataSize),
    ),
    bssVa: GeneratedBssVa,
    bssMemSize: GeneratedBssSize,
    stackPages: U32(2),
  )


## Validates accepted and rejected layouts before filesystem output is involved.
proc runSelfTest(): bool =
  buildGeneratedSections()

  var image = generatedImage()
  if validateRkxImage(image) != RkxWriterOk:
    return false

  image.entryVa = image.rodata.va
  if validateRkxImage(image) != RkxWriterInvalidEntry:
    return false

  image = generatedImage()
  image.rodata.va = image.text.va
  if validateRkxImage(image) != RkxWriterOverlappingSegments:
    return false

  image = generatedImage()
  image.stackPages = U32(17)
  if validateRkxImage(image) != RkxWriterInvalidStackPages:
    return false

  true


## Builds and writes the validation executable to the requested user-owned path.
proc generateImage(path: cstring): bool =
  buildGeneratedSections()

  let image = generatedImage()
  let status = writeRkxImage(path, image)
  if status != RkxWriterOk:
    write("rkxwritecheck: ")
    write(rkxWriterStatusText(status))
    write("\n")
    return false

  if sysChmod(path, U32(0o755)) != 0:
    write("rkxwritecheck: chmod failed\n")
    return false

  true


## Parses the output path and writes a runnable RKX validation image.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == U32(1) and cstringEq(argAt(parsedArgs, U32(0)), cstring("--help")):
    printUsage()
    sysExit(0)

  if parsedArgs.argc == U32(1) and cstringEq(argAt(parsedArgs, U32(0)), cstring("--self-test")):
    if not runSelfTest():
      write("rkxwritecheck: self-test failed\n")
      sysExit(1)

    write("rkxwritecheck: validation ok\n")
    sysExit(0)

  if parsedArgs.argc != U32(1):
    printUsage()
    sysExit(1)

  let path = resolvePath(argAt(parsedArgs, U32(0)))
  if path == nil:
    write("rkxwritecheck: path too long\n")
    sysExit(1)

  if not generateImage(path):
    sysExit(1)

  write("rkxwritecheck: created ")
  write(path)
  write("\n")
  sysExit(0)
