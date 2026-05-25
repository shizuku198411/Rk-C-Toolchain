## Defines and serializes the small relocatable RKO object format.
from lib/syscall_types import SysOpenCreate, SysOpenRead, SysOpenTrunc,
  SysOpenWrite
from lib/types import U8, U32, U64
from user/lib/core/syscall import sysClose, sysOpen, sysReadFd, sysWriteFd


const
  RkoMagic* = U32(0x314f4b52) # "RKO1"
  RkoVersion* = U32(2)
  RkoNameCapacity* = 40
  RkoSectionCapacity* = 16384
  RkoSymbolCapacity* = 64
  RkoRelocationCapacity* = 128

  RkoSectionNone* = U32(0)
  RkoSectionText* = U32(1)
  RkoSectionRodata* = U32(2)
  RkoSectionData* = U32(3)
  RkoSectionBss* = U32(4)

  RkoRelocLa* = U32(1)
  RkoRelocBranch* = U32(2)
  RkoRelocJump* = U32(3)

  RkoSymbolLocal* = U32(0)
  RkoSymbolGlobal* = U32(1)


type
  RkoStatus* = enum
    RkoOk,
    RkoInvalidPath,
    RkoInvalidHeader,
    RkoInvalidObject,
    RkoOpenFailed,
    RkoReadFailed,
    RkoWriteFailed,
    RkoCloseFailed

  RkoHeader* {.packed.} = object
    magic*: U32
    version*: U32
    headerSize*: U32
    textSize*: U32
    rodataSize*: U32
    dataSize*: U32
    bssSize*: U32
    symbolCount*: U32
    relocationCount*: U32
    hasEntry*: U32
    entryName*: array[RkoNameCapacity, char]

  RkoSymbol* {.packed.} = object
    name*: array[RkoNameCapacity, char]
    section*: U32
    offset*: U32
    visibility*: U32

  RkoRelocation* {.packed.} = object
    name*: array[RkoNameCapacity, char]
    kind*: U32
    section*: U32
    offset*: U32
    rd*: U32
    rs1*: U32
    rs2*: U32
    funct3*: U32

  RkoObject* = object
    text*: array[RkoSectionCapacity, U8]
    rodata*: array[RkoSectionCapacity, U8]
    data*: array[RkoSectionCapacity, U8]
    textSize*: U32
    rodataSize*: U32
    dataSize*: U32
    bssSize*: U32
    symbols*: array[RkoSymbolCapacity, RkoSymbol]
    symbolCount*: U32
    relocations*: array[RkoRelocationCapacity, RkoRelocation]
    relocationCount*: U32
    hasEntry*: bool
    entryName*: array[RkoNameCapacity, char]


## Writes every requested byte through bounded file descriptor operations.
proc writeAll(fd: int32, data: pointer, size: U64): bool =
  var offset = U64(0)
  while offset < size:
    var chunk = size - offset
    if chunk > U64(4096):
      chunk = U64(4096)
    let current = cast[pointer](cast[U64](data) + offset)
    let written = sysWriteFd(fd, current, chunk)
    if written <= 0 or U64(written) != chunk:
      return false
    offset = offset + chunk
  true


## Reads exactly the requested byte range from a descriptor.
proc readAll(fd: int32, data: pointer, size: U64): bool =
  var offset = U64(0)
  while offset < size:
    var chunk = size - offset
    if chunk > U64(4096):
      chunk = U64(4096)
    let current = cast[pointer](cast[U64](data) + offset)
    let readLen = sysReadFd(fd, current, chunk)
    if readLen <= 0:
      return false
    offset = offset + U64(readLen)
  true


## Returns whether a section selector is part of the RKO format.
proc validSection(section: U32): bool =
  section >= RkoSectionText and section <= RkoSectionBss


## Validates section sizes, symbol definitions, and relocation records.
proc validateRkoObject*(obj: var RkoObject): RkoStatus =
  if obj.textSize > U32(RkoSectionCapacity) or
      obj.rodataSize > U32(RkoSectionCapacity) or
      obj.dataSize > U32(RkoSectionCapacity) or
      obj.bssSize > U32(RkoSectionCapacity) or
      obj.symbolCount > U32(RkoSymbolCapacity) or
      obj.relocationCount > U32(RkoRelocationCapacity):
    return RkoInvalidObject

  var i = U32(0)
  while i < obj.symbolCount:
    let symbol = obj.symbols[i]
    if not validSection(symbol.section) or symbol.visibility > RkoSymbolGlobal:
      return RkoInvalidObject
    let sectionSize =
      if symbol.section == RkoSectionText: obj.textSize
      elif symbol.section == RkoSectionRodata: obj.rodataSize
      elif symbol.section == RkoSectionData: obj.dataSize
      else: obj.bssSize
    if symbol.offset > sectionSize:
      return RkoInvalidObject
    inc i

  i = U32(0)
  while i < obj.relocationCount:
    let relocation = obj.relocations[i]
    if relocation.section != RkoSectionText or
        relocation.offset + U32(4) > obj.textSize or
        relocation.kind < RkoRelocLa or relocation.kind > RkoRelocJump:
      return RkoInvalidObject
    if relocation.kind == RkoRelocLa and
        relocation.offset + U32(8) > obj.textSize:
      return RkoInvalidObject
    inc i

  RkoOk


## Builds a compact header from one validated in-memory object.
proc buildHeader(obj: var RkoObject): RkoHeader =
  result.magic = RkoMagic
  result.version = RkoVersion
  result.headerSize = U32(sizeof(RkoHeader))
  result.textSize = obj.textSize
  result.rodataSize = obj.rodataSize
  result.dataSize = obj.dataSize
  result.bssSize = obj.bssSize
  result.symbolCount = obj.symbolCount
  result.relocationCount = obj.relocationCount
  result.hasEntry = if obj.hasEntry: U32(1) else: U32(0)
  result.entryName = obj.entryName


## Serializes one relocatable object to a userspace file.
proc writeRkoObject*(path: cstring, obj: var RkoObject): RkoStatus =
  if path == nil or path[0] == '\0':
    return RkoInvalidPath
  let validation = validateRkoObject(obj)
  if validation != RkoOk:
    return validation

  let fd = sysOpen(path, SysOpenWrite or SysOpenCreate or SysOpenTrunc)
  if fd < 0:
    return RkoOpenFailed

  var header = buildHeader(obj)
  let wrote =
    writeAll(fd, addr header, U64(sizeof(RkoHeader))) and
    writeAll(fd, cast[pointer](unsafeAddr obj.text[0]), U64(obj.textSize)) and
    writeAll(fd, cast[pointer](unsafeAddr obj.rodata[0]), U64(obj.rodataSize)) and
    writeAll(fd, cast[pointer](unsafeAddr obj.data[0]), U64(obj.dataSize)) and
    writeAll(fd, cast[pointer](unsafeAddr obj.symbols[0]),
             U64(obj.symbolCount) * U64(sizeof(RkoSymbol))) and
    writeAll(fd, cast[pointer](unsafeAddr obj.relocations[0]),
             U64(obj.relocationCount) * U64(sizeof(RkoRelocation)))
  let closed = sysClose(fd) == 0
  if not wrote:
    return RkoWriteFailed
  if not closed:
    return RkoCloseFailed
  RkoOk


## Reads and validates one serialized relocatable object.
proc readRkoObject*(path: cstring, obj: var RkoObject): RkoStatus =
  if path == nil or path[0] == '\0':
    return RkoInvalidPath
  let fd = sysOpen(path, SysOpenRead)
  if fd < 0:
    return RkoOpenFailed

  obj = RkoObject()
  var header: RkoHeader
  if not readAll(fd, addr header, U64(sizeof(RkoHeader))) or
      header.magic != RkoMagic or header.version != RkoVersion or
      header.headerSize != U32(sizeof(RkoHeader)):
    discard sysClose(fd)
    return RkoInvalidHeader
  if header.textSize > U32(RkoSectionCapacity) or
      header.rodataSize > U32(RkoSectionCapacity) or
      header.dataSize > U32(RkoSectionCapacity) or
      header.bssSize > U32(RkoSectionCapacity) or
      header.symbolCount > U32(RkoSymbolCapacity) or
      header.relocationCount > U32(RkoRelocationCapacity) or
      header.hasEntry > U32(1):
    discard sysClose(fd)
    return RkoInvalidHeader

  obj.textSize = header.textSize
  obj.rodataSize = header.rodataSize
  obj.dataSize = header.dataSize
  obj.bssSize = header.bssSize
  obj.symbolCount = header.symbolCount
  obj.relocationCount = header.relocationCount
  obj.hasEntry = header.hasEntry == U32(1)
  obj.entryName = header.entryName

  let readOk =
    readAll(fd, addr obj.text[0], U64(obj.textSize)) and
    readAll(fd, addr obj.rodata[0], U64(obj.rodataSize)) and
    readAll(fd, addr obj.data[0], U64(obj.dataSize)) and
    readAll(fd, addr obj.symbols[0],
            U64(obj.symbolCount) * U64(sizeof(RkoSymbol))) and
    readAll(fd, addr obj.relocations[0],
            U64(obj.relocationCount) * U64(sizeof(RkoRelocation)))
  let closed = sysClose(fd) == 0
  if not readOk:
    return RkoReadFailed
  if not closed:
    return RkoCloseFailed
  validateRkoObject(obj)


## Returns a printable diagnostic for an object I/O or format result.
proc rkoStatusText*(status: RkoStatus): cstring =
  case status
  of RkoOk: cstring("ok")
  of RkoInvalidPath: cstring("invalid path")
  of RkoInvalidHeader: cstring("invalid object header")
  of RkoInvalidObject: cstring("invalid object contents")
  of RkoOpenFailed: cstring("open failed")
  of RkoReadFailed: cstring("read failed")
  of RkoWriteFailed: cstring("write failed")
  of RkoCloseFailed: cstring("close failed")
