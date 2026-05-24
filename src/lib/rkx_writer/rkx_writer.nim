## Emits validated, unprivileged RKX executable images from classified segments.
from lib/rkx import RkxAllowedUidMax, RkxDefaultStackPages, RkxHeader,
  RkxMagic, RkxMaxStackPages, RkxMinStackPages, RkxVersion
from lib/syscall_types import SysOpenCreate, SysOpenTrunc, SysOpenWrite
from lib/types import PageSize, U8, U32, U64, isAligned
from user/lib/core/syscall import sysClose, sysOpen, sysWriteFd


const
  RkxWriterUserBase* = U64(0x01200000)
  RkxWriterImageVaLimit* = RkxWriterUserBase + U64(0x00100000)
  RkxWriterMaxImageSize* = U64(64) * PageSize


type
  RkxWriterStatus* = enum
    RkxWriterOk,
    RkxWriterInvalidPath,
    RkxWriterInvalidStackPages,
    RkxWriterInvalidSegment,
    RkxWriterOverlappingSegments,
    RkxWriterInvalidEntry,
    RkxWriterImageTooLarge,
    RkxWriterOpenFailed,
    RkxWriterWriteFailed,
    RkxWriterCloseFailed

  RkxSegmentInput* = object
    va*: U64
    data*: pointer
    fileSize*: U64
    memSize*: U64

  RkxImageInput* = object
    entryVa*: U64
    text*: RkxSegmentInput
    rodata*: RkxSegmentInput
    data*: RkxSegmentInput
    bssVa*: U64
    bssMemSize*: U64
    stackPages*: U32


## Returns whether adding two unsigned values is representable.
proc checkedAdd(a, b: U64, outValue: var U64): bool =
  outValue = a + b
  outValue >= a


## Returns whether a non-empty virtual memory interval is inside the user image window.
proc validMemoryRange(va, memSize: U64): bool =
  if memSize == U64(0):
    return true

  if not isAligned(va, PageSize):
    return false

  var rangeEnd = U64(0)
  if not checkedAdd(va, memSize, rangeEnd):
    return false

  va >= RkxWriterUserBase and rangeEnd <= RkxWriterImageVaLimit


## Returns whether a supplied file-backed segment is structurally valid.
proc validSegment(segment: RkxSegmentInput): bool =
  if segment.memSize == U64(0):
    return segment.fileSize == U64(0)

  if segment.fileSize > segment.memSize:
    return false

  if segment.fileSize > U64(0) and segment.data == nil:
    return false

  validMemoryRange(segment.va, segment.memSize)


## Returns whether two virtual memory ranges overlap.
proc overlaps(firstVa, firstSize, secondVa, secondSize: U64): bool =
  if firstSize == U64(0) or secondSize == U64(0):
    return false

  var firstEnd = U64(0)
  var secondEnd = U64(0)
  if not checkedAdd(firstVa, firstSize, firstEnd) or
      not checkedAdd(secondVa, secondSize, secondEnd):
    return true

  firstVa < secondEnd and secondVa < firstEnd


## Returns whether any input segment would occupy another segment's virtual range.
proc hasSegmentOverlap(image: RkxImageInput): bool =
  if overlaps(image.text.va, image.text.memSize, image.rodata.va, image.rodata.memSize):
    return true
  if overlaps(image.text.va, image.text.memSize, image.data.va, image.data.memSize):
    return true
  if overlaps(image.text.va, image.text.memSize, image.bssVa, image.bssMemSize):
    return true
  if overlaps(image.rodata.va, image.rodata.memSize, image.data.va, image.data.memSize):
    return true
  if overlaps(image.rodata.va, image.rodata.memSize, image.bssVa, image.bssMemSize):
    return true

  overlaps(image.data.va, image.data.memSize, image.bssVa, image.bssMemSize)


## Computes the serialized size while rejecting offset overflow and oversized images.
proc imageFileSize(image: RkxImageInput, outValue: var U64): bool =
  outValue = U64(sizeof(RkxHeader))

  if not checkedAdd(outValue, image.text.fileSize, outValue):
    return false
  if not checkedAdd(outValue, image.rodata.fileSize, outValue):
    return false
  if not checkedAdd(outValue, image.data.fileSize, outValue):
    return false

  outValue <= RkxWriterMaxImageSize


## Validates input using the same externally visible constraints as the kernel loader.
proc validateRkxImage*(image: RkxImageInput): RkxWriterStatus =
  if image.stackPages != U32(0) and
      (image.stackPages < RkxMinStackPages or image.stackPages > RkxMaxStackPages):
    return RkxWriterInvalidStackPages

  if not validSegment(image.text) or not validSegment(image.rodata) or
      not validSegment(image.data):
    return RkxWriterInvalidSegment

  if image.bssMemSize > U64(0) and not validMemoryRange(image.bssVa, image.bssMemSize):
    return RkxWriterInvalidSegment

  if hasSegmentOverlap(image):
    return RkxWriterOverlappingSegments

  if image.text.memSize == U64(0):
    return RkxWriterInvalidEntry

  var textEnd = U64(0)
  if not checkedAdd(image.text.va, image.text.memSize, textEnd) or
      image.entryVa < image.text.va or image.entryVa >= textEnd:
    return RkxWriterInvalidEntry

  var fileSize = U64(0)
  if not imageFileSize(image, fileSize):
    return RkxWriterImageTooLarge

  RkxWriterOk


## Fills an RKX header for an already validated unprivileged image.
proc buildHeader(image: RkxImageInput): RkxHeader =
  var header = RkxHeader()
  var offset = U64(sizeof(RkxHeader))

  header.magic = RkxMagic
  header.version = RkxVersion
  header.headerSize = U32(sizeof(RkxHeader))
  header.capabilityMask = U32(0)
  header.entryVa = image.entryVa

  header.textVa = image.text.va
  header.textOff = offset
  header.textFileSize = image.text.fileSize
  header.textMemSize = image.text.memSize
  offset = offset + image.text.fileSize

  header.rodataVa = image.rodata.va
  header.rodataOff = offset
  header.rodataFileSize = image.rodata.fileSize
  header.rodataMemSize = image.rodata.memSize
  offset = offset + image.rodata.fileSize

  header.dataVa = image.data.va
  header.dataOff = offset
  header.dataFileSize = image.data.fileSize
  header.dataMemSize = image.data.memSize

  header.bssVa = image.bssVa
  header.bssMemSize = image.bssMemSize
  header.stackPages =
    if image.stackPages == U32(0):
      RkxDefaultStackPages
    else:
      image.stackPages
  header.flags = U32(0)
  header.allowedUidCount = U32(0)
  header.reserved = U32(0)

  var i = 0
  while i < RkxAllowedUidMax:
    header.allowedUids[i] = U32(0)
    inc i

  header


## Writes every requested byte to an output descriptor using bounded FD writes.
proc writeAll(fd: int32, data: pointer, size: U64): bool =
  if size == U64(0):
    return true

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


## Writes an RKX image to a normal userspace file with no requested privileges.
proc writeRkxImage*(path: cstring, image: RkxImageInput): RkxWriterStatus =
  if path == nil or path[0] == '\0':
    return RkxWriterInvalidPath

  let validation = validateRkxImage(image)
  if validation != RkxWriterOk:
    return validation

  let fd = sysOpen(path, SysOpenWrite or SysOpenCreate or SysOpenTrunc)
  if fd < 0:
    return RkxWriterOpenFailed

  var header = buildHeader(image)
  let wrote =
    writeAll(fd, addr header, U64(sizeof(RkxHeader))) and
    writeAll(fd, image.text.data, image.text.fileSize) and
    writeAll(fd, image.rodata.data, image.rodata.fileSize) and
    writeAll(fd, image.data.data, image.data.fileSize)

  let closed = sysClose(fd) == 0
  if not wrote:
    return RkxWriterWriteFailed
  if not closed:
    return RkxWriterCloseFailed

  RkxWriterOk


## Returns a printable diagnostic label for one RKX writer result.
proc rkxWriterStatusText*(status: RkxWriterStatus): cstring =
  case status
  of RkxWriterOk: cstring("ok")
  of RkxWriterInvalidPath: cstring("invalid path")
  of RkxWriterInvalidStackPages: cstring("invalid stack pages")
  of RkxWriterInvalidSegment: cstring("invalid segment")
  of RkxWriterOverlappingSegments: cstring("overlapping segments")
  of RkxWriterInvalidEntry: cstring("invalid entry")
  of RkxWriterImageTooLarge: cstring("image too large")
  of RkxWriterOpenFailed: cstring("open failed")
  of RkxWriterWriteFailed: cstring("write failed")
  of RkxWriterCloseFailed: cstring("close failed")
