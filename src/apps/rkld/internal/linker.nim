## Links RKO sections and relocations into one executable RKX image descriptor.
from lib/types import I64, PageSize, U8, U32, U64, alignUp
import lib/rko_format/rko
import lib/rkx_writer/rkx_writer
import ../../rkas/internal/encoder


const
  LinkObjectCapacity* = 8
  LinkSectionCapacity = RkoSectionCapacity * 4
  LinkSymbolCapacity = RkoSymbolCapacity * 4
  LinkRelocationCapacity = RkoRelocationCapacity * 4


type
  LinkStatus* = enum
    LinkOk,
    LinkInvalidObject,
    LinkSectionOverflow,
    LinkTooManySymbols,
    LinkDuplicateSymbol,
    LinkTooManyRelocations,
    LinkDuplicateEntry,
    LinkMissingEntry,
    LinkUnknownSymbol,
    LinkRelocationRange,
    LinkInvalidImage

  LinkSymbol = object
    name: array[RkoNameCapacity, char]
    section: U32
    offset: U32
    visibility: U32
    objectId: U32

  LinkRelocation = object
    name: array[RkoNameCapacity, char]
    kind: U32
    offset: U32
    rd: U32
    rs1: U32
    rs2: U32
    funct3: U32
    objectId: U32

  LinkState* = object
    text: array[LinkSectionCapacity, U8]
    rodata: array[LinkSectionCapacity, U8]
    data: array[LinkSectionCapacity, U8]
    textSize: U32
    rodataSize: U32
    dataSize: U32
    bssSize: U32
    symbols: array[LinkSymbolCapacity, LinkSymbol]
    symbolCount: U32
    relocations: array[LinkRelocationCapacity, LinkRelocation]
    relocationCount: U32
    entryName: array[RkoNameCapacity, char]
    entryObjectId: U32
    hasEntry: bool
    objectCount: U32


## Copies one fixed object-format symbol name.
proc copyName(dst: var array[RkoNameCapacity, char],
              src: array[RkoNameCapacity, char]) =
  var i = 0
  while i < RkoNameCapacity:
    dst[i] = src[i]
    inc i


## Compares fixed symbol buffers for exact equality.
proc sameName(left, right: array[RkoNameCapacity, char]): bool =
  var i = 0
  while i < RkoNameCapacity:
    if left[i] != right[i]:
      return false
    if left[i] == '\0':
      return true
    inc i
  true


## Initializes one empty link aggregation state.
proc initLinkState*(state: var LinkState) =
  state = LinkState()


## Returns the output virtual address selected for one aggregate section.
proc sectionBase(state: var LinkState, section: U32): U64 =
  if section == RkoSectionText:
    return RkxWriterUserBase
  if section == RkoSectionRodata:
    return RkxWriterUserBase + alignUp(U64(state.textSize), PageSize)
  if section == RkoSectionData:
    return state.sectionBase(RkoSectionRodata) +
      alignUp(U64(state.rodataSize), PageSize)
  if section == RkoSectionBss:
    return state.sectionBase(RkoSectionData) +
      alignUp(U64(state.dataSize), PageSize)
  U64(0)


## Returns a section-relative aggregate offset after appending an object.
proc mappedOffset(section, offset, textBase, rodataBase, dataBase,
                  bssBase: U32): U32 =
  if section == RkoSectionText:
    return textBase + offset
  if section == RkoSectionRodata:
    return rodataBase + offset
  if section == RkoSectionData:
    return dataBase + offset
  bssBase + offset


## Resolves a local symbol in the requester first, then one exported symbol.
proc symbolAddress(state: var LinkState,
                   name: array[RkoNameCapacity, char], objectId: U32,
                   value: var U64): bool =
  var i = U32(0)
  while i < state.symbolCount:
    if state.symbols[i].visibility == RkoSymbolLocal and
        state.symbols[i].objectId == objectId and
        sameName(state.symbols[i].name, name):
      value = state.sectionBase(state.symbols[i].section) +
        U64(state.symbols[i].offset)
      return true
    inc i
  i = U32(0)
  while i < state.symbolCount:
    if state.symbols[i].visibility == RkoSymbolGlobal and
        sameName(state.symbols[i].name, name):
      value = state.sectionBase(state.symbols[i].section) +
        U64(state.symbols[i].offset)
      return true
    inc i
  false


## Returns whether a symbol name is already globally defined.
proc hasGlobalSymbol(state: var LinkState,
                     name: array[RkoNameCapacity, char]): bool =
  var i = U32(0)
  while i < state.symbolCount:
    if state.symbols[i].visibility == RkoSymbolGlobal and
        sameName(state.symbols[i].name, name):
      return true
    inc i
  false


## Copies a section's used bytes into its aggregate destination.
proc appendBytes(dst: var array[LinkSectionCapacity, U8], used: var U32,
                 src: pointer, size: U32): bool =
  if used + size > U32(LinkSectionCapacity):
    return false
  let input = cast[ptr UncheckedArray[U8]](src)
  var i = U32(0)
  while i < size:
    dst[used + i] = input[i]
    inc i
  used = used + size
  true


## Adds one input object to the aggregate, preserving unresolved relocations.
proc addObject*(state: var LinkState, obj: var RkoObject): LinkStatus =
  if state.objectCount >= U32(LinkObjectCapacity) or
      validateRkoObject(obj) != RkoOk:
    return LinkInvalidObject
  if state.textSize + obj.textSize > U32(LinkSectionCapacity) or
      state.rodataSize + obj.rodataSize > U32(LinkSectionCapacity) or
      state.dataSize + obj.dataSize > U32(LinkSectionCapacity) or
      state.bssSize + obj.bssSize > U32(LinkSectionCapacity):
    return LinkSectionOverflow
  if state.symbolCount + obj.symbolCount > U32(LinkSymbolCapacity):
    return LinkTooManySymbols
  if state.relocationCount + obj.relocationCount > U32(LinkRelocationCapacity):
    return LinkTooManyRelocations
  if state.hasEntry and obj.hasEntry:
    return LinkDuplicateEntry

  let textBase = state.textSize
  let rodataBase = state.rodataSize
  let dataBase = state.dataSize
  let bssBase = state.bssSize
  let objectId = state.objectCount
  if not appendBytes(state.text, state.textSize,
                     cast[pointer](unsafeAddr obj.text[0]), obj.textSize) or
      not appendBytes(state.rodata, state.rodataSize,
                     cast[pointer](unsafeAddr obj.rodata[0]), obj.rodataSize) or
      not appendBytes(state.data, state.dataSize,
                     cast[pointer](unsafeAddr obj.data[0]), obj.dataSize):
    return LinkSectionOverflow
  state.bssSize = state.bssSize + obj.bssSize

  var i = U32(0)
  while i < obj.symbolCount:
    if obj.symbols[i].visibility == RkoSymbolGlobal and
        state.hasGlobalSymbol(obj.symbols[i].name):
      return LinkDuplicateSymbol
    let target = state.symbolCount
    copyName(state.symbols[target].name, obj.symbols[i].name)
    state.symbols[target].section = obj.symbols[i].section
    state.symbols[target].offset = mappedOffset(
      obj.symbols[i].section, obj.symbols[i].offset,
      textBase, rodataBase, dataBase, bssBase)
    state.symbols[target].visibility = obj.symbols[i].visibility
    state.symbols[target].objectId = objectId
    inc state.symbolCount
    inc i

  i = U32(0)
  while i < obj.relocationCount:
    let target = state.relocationCount
    copyName(state.relocations[target].name, obj.relocations[i].name)
    state.relocations[target].kind = obj.relocations[i].kind
    state.relocations[target].offset = textBase + obj.relocations[i].offset
    state.relocations[target].rd = obj.relocations[i].rd
    state.relocations[target].rs1 = obj.relocations[i].rs1
    state.relocations[target].rs2 = obj.relocations[i].rs2
    state.relocations[target].funct3 = obj.relocations[i].funct3
    state.relocations[target].objectId = objectId
    inc state.relocationCount
    inc i

  if obj.hasEntry:
    state.hasEntry = true
    copyName(state.entryName, obj.entryName)
    state.entryObjectId = objectId
  inc state.objectCount
  LinkOk


## Overwrites one instruction in the aggregate text after relocation resolution.
proc patchInstruction(state: var LinkState, offset, value: U32): bool =
  if offset + U32(4) > state.textSize:
    return false
  state.text[offset] = U8(value and U32(0xff))
  state.text[offset + U32(1)] = U8((value shr U32(8)) and U32(0xff))
  state.text[offset + U32(2)] = U8((value shr U32(16)) and U32(0xff))
  state.text[offset + U32(3)] = U8((value shr U32(24)) and U32(0xff))
  true


## Resolves all cross-object and same-object label references at final addresses.
proc applyRelocations(state: var LinkState): LinkStatus =
  var i = U32(0)
  while i < state.relocationCount:
    let relocation = state.relocations[i]
    var target = U64(0)
    if not state.symbolAddress(relocation.name, relocation.objectId, target):
      return LinkUnknownSymbol
    let location = state.sectionBase(RkoSectionText) + U64(relocation.offset)
    let displacement = I64(target) - I64(location)
    var first, second = U32(0)
    if relocation.kind == RkoRelocLa:
      if not encodeLa(relocation.rd, displacement, first, second) or
          not state.patchInstruction(relocation.offset, first) or
          not state.patchInstruction(relocation.offset + U32(4), second):
        return LinkRelocationRange
    elif relocation.kind == RkoRelocBranch:
      if not encodeB(relocation.funct3, relocation.rs1, relocation.rs2,
                     displacement, first) or
          not state.patchInstruction(relocation.offset, first):
        return LinkRelocationRange
    elif relocation.kind == RkoRelocJump:
      if not encodeJ(relocation.rd, displacement, first) or
          not state.patchInstruction(relocation.offset, first):
        return LinkRelocationRange
    else:
      return LinkInvalidObject
    inc i
  LinkOk


## Resolves a linked image and returns RKX writer input backed by link state buffers.
proc finishLink*(state: var LinkState, image: var RkxImageInput): LinkStatus =
  if not state.hasEntry:
    return LinkMissingEntry
  var entry = U64(0)
  if not state.symbolAddress(state.entryName, state.entryObjectId, entry):
    return LinkUnknownSymbol
  let relocationStatus = state.applyRelocations()
  if relocationStatus != LinkOk:
    return relocationStatus

  image = RkxImageInput(
    entryVa: entry,
    text: RkxSegmentInput(
      va: state.sectionBase(RkoSectionText),
      data: addr state.text[0],
      fileSize: U64(state.textSize),
      memSize: U64(state.textSize),
    ),
    rodata: RkxSegmentInput(
      va: state.sectionBase(RkoSectionRodata),
      data: addr state.rodata[0],
      fileSize: U64(state.rodataSize),
      memSize: U64(state.rodataSize),
    ),
    data: RkxSegmentInput(
      va: state.sectionBase(RkoSectionData),
      data: addr state.data[0],
      fileSize: U64(state.dataSize),
      memSize: U64(state.dataSize),
    ),
    bssVa: state.sectionBase(RkoSectionBss),
    bssMemSize: U64(state.bssSize),
    stackPages: U32(2),
  )
  if validateRkxImage(image) != RkxWriterOk:
    return LinkInvalidImage
  LinkOk


## Returns a stable user-facing linker status description.
proc linkStatusText*(status: LinkStatus): cstring =
  case status
  of LinkOk: cstring("ok")
  of LinkInvalidObject: cstring("invalid object")
  of LinkSectionOverflow: cstring("linked section too large")
  of LinkTooManySymbols: cstring("too many symbols")
  of LinkDuplicateSymbol: cstring("duplicate symbol")
  of LinkTooManyRelocations: cstring("too many relocations")
  of LinkDuplicateEntry: cstring("multiple entry points")
  of LinkMissingEntry: cstring("missing entry point")
  of LinkUnknownSymbol: cstring("unknown symbol")
  of LinkRelocationRange: cstring("relocation out of range")
  of LinkInvalidImage: cstring("invalid output image")
