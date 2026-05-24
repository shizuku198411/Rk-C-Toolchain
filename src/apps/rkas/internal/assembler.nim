## Parses the initial rkas syntax and emits classified sections through RKX writer inputs.
from lib/types import I64, U8, U32, U64
from user/lib/core/strutils import isSpace
import lib/rkx_writer/rkx_writer
import ./encoder


const
  SectionCapacity = 4096
  LineCapacity = 192
  TokenCapacity = 8
  TokenLength = 40
  LabelCapacity = 64
  RelocationCapacity = 128


type
  AsmStatus* = enum
    AsmOk,
    AsmSourceTooLarge,
    AsmLineTooLong,
    AsmSyntaxError,
    AsmUnknownDirective,
    AsmUnknownInstruction,
    AsmInvalidRegister,
    AsmInvalidImmediate,
    AsmWrongSection,
    AsmSectionOverflow,
    AsmTooManyLabels,
    AsmDuplicateLabel,
    AsmMissingEntry,
    AsmUnknownLabel,
    AsmTooManyRelocations,
    AsmRelocationRange,
    AsmInvalidImage

  SectionKind = enum
    SectionNone,
    SectionText,
    SectionRodata,
    SectionData,
    SectionBss

  RelocationKind = enum
    RelocLa,
    RelocBranch,
    RelocJump

  LabelEntry = object
    name: array[TokenLength, char]
    section: SectionKind
    offset: U32

  RelocationEntry = object
    name: array[TokenLength, char]
    kind: RelocationKind
    offset: U32
    rd: U32
    rs1: U32
    rs2: U32
    funct3: U32

  AsmState = object
    section: SectionKind
    text: array[SectionCapacity, U8]
    rodata: array[SectionCapacity, U8]
    data: array[SectionCapacity, U8]
    textLen: U32
    rodataLen: U32
    dataLen: U32
    bssLen: U32
    labels: array[LabelCapacity, LabelEntry]
    labelCount: U32
    relocations: array[RelocationCapacity, RelocationEntry]
    relocationCount: U32
    entryName: array[TokenLength, char]
    hasEntry: bool


var state: AsmState


## Copies a token name into fixed assembly state storage.
proc copyName(dst: var array[TokenLength, char], src: cstring): bool =
  var i = 0
  while src[i] != '\0':
    if i + 1 >= TokenLength:
      return false
    dst[i] = src[i]
    inc i
  dst[i] = '\0'
  true


## Compares a stored assembly name to a token string.
proc sameName(stored: var array[TokenLength, char], name: cstring): bool =
  var i = 0
  while stored[i] != '\0' and name[i] != '\0':
    if stored[i] != name[i]:
      return false
    inc i
  stored[i] == '\0' and name[i] == '\0'


## Returns the current offset within whichever section is active.
proc currentOffset(): U32 =
  case state.section
  of SectionText: state.textLen
  of SectionRodata: state.rodataLen
  of SectionData: state.dataLen
  of SectionBss: state.bssLen
  else: U32(0)


## Returns the fixed virtual base of one generated section.
proc sectionBase(section: SectionKind): U64 =
  case section
  of SectionText: RkxWriterUserBase
  of SectionRodata: RkxWriterUserBase + U64(0x1000)
  of SectionData: RkxWriterUserBase + U64(0x2000)
  of SectionBss: RkxWriterUserBase + U64(0x3000)
  else: U64(0)


## Appends a byte to the current file-backed section or reserves one BSS byte.
proc appendByte(value: U8): bool =
  case state.section
  of SectionText:
    if state.textLen >= U32(SectionCapacity):
      return false
    state.text[state.textLen] = value
    inc state.textLen
  of SectionRodata:
    if state.rodataLen >= U32(SectionCapacity):
      return false
    state.rodata[state.rodataLen] = value
    inc state.rodataLen
  of SectionData:
    if state.dataLen >= U32(SectionCapacity):
      return false
    state.data[state.dataLen] = value
    inc state.dataLen
  of SectionBss:
    if state.bssLen >= U32(SectionCapacity):
      return false
    inc state.bssLen
  else:
    return false
  true


## Writes one encoded instruction word into the text section.
proc appendInstruction(value: U32): bool =
  if state.section != SectionText:
    return false

  appendByte(U8(value and U32(0xff))) and
    appendByte(U8((value shr U32(8)) and U32(0xff))) and
    appendByte(U8((value shr U32(16)) and U32(0xff))) and
    appendByte(U8((value shr U32(24)) and U32(0xff)))


## Overwrites a text word after a label relocation has been resolved.
proc patchInstruction(offset, value: U32): bool =
  if offset + U32(4) > state.textLen:
    return false
  state.text[offset] = U8(value and U32(0xff))
  state.text[offset + U32(1)] = U8((value shr U32(8)) and U32(0xff))
  state.text[offset + U32(2)] = U8((value shr U32(16)) and U32(0xff))
  state.text[offset + U32(3)] = U8((value shr U32(24)) and U32(0xff))
  true


## Parses decimal or hexadecimal integer syntax with an optional minus sign.
proc parseInteger(token: cstring, value: var I64): bool =
  if token == nil or token[0] == '\0':
    return false

  var negative = false
  var pos = 0
  if token[pos] == '-':
    negative = true
    inc pos

  var base = I64(10)
  if token[pos] == '0' and (token[pos + 1] == 'x' or token[pos + 1] == 'X'):
    base = I64(16)
    pos += 2

  var parsed = I64(0)
  var found = false
  while token[pos] != '\0':
    var digit = I64(-1)
    if token[pos] >= '0' and token[pos] <= '9':
      digit = I64(ord(token[pos]) - ord('0'))
    elif token[pos] >= 'a' and token[pos] <= 'f':
      digit = I64(ord(token[pos]) - ord('a') + 10)
    elif token[pos] >= 'A' and token[pos] <= 'F':
      digit = I64(ord(token[pos]) - ord('A') + 10)
    else:
      return false

    if digit >= base:
      return false
    parsed = parsed * base + digit
    found = true
    inc pos

  if not found:
    return false
  value = if negative: -parsed else: parsed
  true


## Returns the register number for an integer register or ABI alias.
proc registerNumber(token: cstring, value: var U32): bool =
  const aliases = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
  ]

  if token[0] == 'x':
    var parsed = I64(0)
    if parseInteger(cast[cstring](addr token[1]), parsed) and
        parsed >= I64(0) and parsed <= I64(31):
      value = U32(parsed)
      return true

  var i = 0
  while i < aliases.len:
    var tokenLen = 0
    while token[tokenLen] != '\0':
      inc tokenLen
    if tokenLen != aliases[i].len:
      inc i
      continue

    var matched = true
    var p = 0
    while p < aliases[i].len:
      if aliases[i][p] != token[p]:
        matched = false
        break
      inc p
    if matched:
      value = U32(i)
      return true
    inc i

  false


## Records a label at the current section position.
proc addLabel(name: cstring): AsmStatus =
  if state.section == SectionNone:
    return AsmWrongSection

  var i = U32(0)
  while i < state.labelCount:
    if sameName(state.labels[i].name, name):
      return AsmDuplicateLabel
    inc i

  if state.labelCount >= U32(LabelCapacity):
    return AsmTooManyLabels

  if not copyName(state.labels[state.labelCount].name, name):
    return AsmSyntaxError
  state.labels[state.labelCount].section = state.section
  state.labels[state.labelCount].offset = currentOffset()
  inc state.labelCount
  AsmOk


## Looks up an existing label and computes its fixed virtual address.
proc labelAddress(name: cstring, value: var U64): bool =
  var i = U32(0)
  while i < state.labelCount:
    if sameName(state.labels[i].name, name):
      value = sectionBase(state.labels[i].section) + U64(state.labels[i].offset)
      return true
    inc i
  false


## Adds an instruction relocation for resolution after all labels are known.
proc addRelocation(kind: RelocationKind, name: cstring, offset, rd, rs1, rs2,
                   funct3: U32): AsmStatus =
  if state.relocationCount >= U32(RelocationCapacity):
    return AsmTooManyRelocations

  let index = state.relocationCount
  if not copyName(state.relocations[index].name, name):
    return AsmSyntaxError
  state.relocations[index].kind = kind
  state.relocations[index].offset = offset
  state.relocations[index].rd = rd
  state.relocations[index].rs1 = rs1
  state.relocations[index].rs2 = rs2
  state.relocations[index].funct3 = funct3
  inc state.relocationCount
  AsmOk


## Splits instruction or directive operands at whitespace and comma separators.
proc tokenize(line: cstring, tokens: var array[TokenCapacity, array[TokenLength, char]],
              count: var U32): bool =
  count = U32(0)
  var pos = 0
  while line[pos] != '\0':
    while isSpace(line[pos]) or line[pos] == ',':
      inc pos
    if line[pos] == '\0' or line[pos] == '#':
      break
    if count >= U32(TokenCapacity):
      return false

    var len = 0
    while line[pos] != '\0' and not isSpace(line[pos]) and
        line[pos] != ',' and line[pos] != '#':
      if len + 1 >= TokenLength:
        return false
      tokens[count][len] = line[pos]
      inc len
      inc pos
    tokens[count][len] = '\0'
    inc count
  true


## Compares a parsed token with a static syntax word.
proc tokenIs(token: var array[TokenLength, char], expected: cstring): bool =
  sameName(token, expected)


## Parses an offset(base) load/store operand.
proc parseMemoryOperand(token: cstring, offset: var I64, base: var U32): bool =
  var immediate: array[TokenLength, char]
  var register: array[TokenLength, char]
  var pos = 0
  var len = 0
  while token[pos] != '\0' and token[pos] != '(':
    if len + 1 >= TokenLength:
      return false
    immediate[len] = token[pos]
    inc len
    inc pos
  immediate[len] = '\0'
  if token[pos] != '(':
    return false
  inc pos
  len = 0
  while token[pos] != '\0' and token[pos] != ')':
    if len + 1 >= TokenLength:
      return false
    register[len] = token[pos]
    inc len
    inc pos
  register[len] = '\0'
  if token[pos] != ')' or token[pos + 1] != '\0':
    return false
  parseInteger(cast[cstring](addr immediate[0]), offset) and
    registerNumber(cast[cstring](addr register[0]), base)


## Emits one instruction or queues its label-dependent relocation.
proc emitInstruction(tokens: var array[TokenCapacity, array[TokenLength, char]],
                     count: U32): AsmStatus =
  if state.section != SectionText:
    return AsmWrongSection

  let op = cast[cstring](addr tokens[0][0])
  var rd, rs1, rs2 = U32(0)
  var immediate = I64(0)
  var encoded, second = U32(0)

  if tokenIs(tokens[0], cstring("ecall")) and count == U32(1):
    return if appendInstruction(U32(0x00000073)): AsmOk else: AsmSectionOverflow
  if tokenIs(tokens[0], cstring("ret")) and count == U32(1):
    return if appendInstruction(U32(0x00008067)): AsmOk else: AsmSectionOverflow

  if tokenIs(tokens[0], cstring("li")) and count == U32(3):
    if not registerNumber(cast[cstring](addr tokens[1][0]), rd):
      return AsmInvalidRegister
    if not parseInteger(cast[cstring](addr tokens[2][0]), immediate):
      return AsmInvalidImmediate
    var words = U32(0)
    if not encodeLi(rd, immediate, encoded, second, words):
      return AsmInvalidImmediate
    if not appendInstruction(encoded):
      return AsmSectionOverflow
    if words == U32(2) and not appendInstruction(second):
      return AsmSectionOverflow
    return AsmOk

  if tokenIs(tokens[0], cstring("la")) and count == U32(3):
    if not registerNumber(cast[cstring](addr tokens[1][0]), rd):
      return AsmInvalidRegister
    let offset = state.textLen
    if not appendInstruction(U32(0)) or not appendInstruction(U32(0)):
      return AsmSectionOverflow
    return addRelocation(RelocLa, cast[cstring](addr tokens[2][0]), offset, rd, U32(0), U32(0), U32(0))

  if tokenIs(tokens[0], cstring("addi")) and count == U32(4):
    if not registerNumber(cast[cstring](addr tokens[1][0]), rd) or
        not registerNumber(cast[cstring](addr tokens[2][0]), rs1):
      return AsmInvalidRegister
    if not parseInteger(cast[cstring](addr tokens[3][0]), immediate) or
        not encodeI(U32(0x13), U32(0), rd, rs1, immediate, encoded):
      return AsmInvalidImmediate
    return if appendInstruction(encoded): AsmOk else: AsmSectionOverflow

  if (tokenIs(tokens[0], cstring("add")) or tokenIs(tokens[0], cstring("sub"))) and count == U32(4):
    if not registerNumber(cast[cstring](addr tokens[1][0]), rd) or
        not registerNumber(cast[cstring](addr tokens[2][0]), rs1) or
        not registerNumber(cast[cstring](addr tokens[3][0]), rs2):
      return AsmInvalidRegister
    encoded = encodeR(
      if tokenIs(tokens[0], cstring("sub")): U32(0x20) else: U32(0),
      U32(0), rd, rs1, rs2)
    return if appendInstruction(encoded): AsmOk else: AsmSectionOverflow

  if (tokenIs(tokens[0], cstring("ld")) or tokenIs(tokens[0], cstring("lw")) or
      tokenIs(tokens[0], cstring("lbu"))) and count == U32(3):
    if not registerNumber(cast[cstring](addr tokens[1][0]), rd) or
        not parseMemoryOperand(cast[cstring](addr tokens[2][0]), immediate, rs1):
      return AsmSyntaxError
    let funct3 =
      if tokenIs(tokens[0], cstring("ld")): U32(3)
      elif tokenIs(tokens[0], cstring("lw")): U32(2)
      else: U32(4)
    if not encodeI(U32(0x03), funct3, rd, rs1, immediate, encoded):
      return AsmInvalidImmediate
    return if appendInstruction(encoded): AsmOk else: AsmSectionOverflow

  if (tokenIs(tokens[0], cstring("sd")) or tokenIs(tokens[0], cstring("sw")) or
      tokenIs(tokens[0], cstring("sb"))) and count == U32(3):
    if not registerNumber(cast[cstring](addr tokens[1][0]), rs2) or
        not parseMemoryOperand(cast[cstring](addr tokens[2][0]), immediate, rs1):
      return AsmSyntaxError
    let funct3 =
      if tokenIs(tokens[0], cstring("sd")): U32(3)
      elif tokenIs(tokens[0], cstring("sw")): U32(2)
      else: U32(0)
    if not encodeS(funct3, rs1, rs2, immediate, encoded):
      return AsmInvalidImmediate
    return if appendInstruction(encoded): AsmOk else: AsmSectionOverflow

  if (tokenIs(tokens[0], cstring("beq")) or tokenIs(tokens[0], cstring("bne"))) and count == U32(4):
    if not registerNumber(cast[cstring](addr tokens[1][0]), rs1) or
        not registerNumber(cast[cstring](addr tokens[2][0]), rs2):
      return AsmInvalidRegister
    let offset = state.textLen
    if not appendInstruction(U32(0)):
      return AsmSectionOverflow
    return addRelocation(
      RelocBranch, cast[cstring](addr tokens[3][0]), offset, U32(0), rs1, rs2,
      if tokenIs(tokens[0], cstring("bne")): U32(1) else: U32(0))

  if (tokenIs(tokens[0], cstring("j")) or tokenIs(tokens[0], cstring("call"))) and count == U32(2):
    let offset = state.textLen
    if not appendInstruction(U32(0)):
      return AsmSectionOverflow
    return addRelocation(
      RelocJump, cast[cstring](addr tokens[1][0]), offset,
      if tokenIs(tokens[0], cstring("call")): U32(1) else: U32(0),
      U32(0), U32(0), U32(0))

  discard op
  AsmUnknownInstruction


## Emits bytes for one directive after section and entry directives are handled.
proc emitDataDirective(line: cstring,
                       tokens: var array[TokenCapacity, array[TokenLength, char]],
                       count: U32): AsmStatus =
  if tokenIs(tokens[0], cstring(".zero")) and count == U32(2):
    var size = I64(0)
    if not parseInteger(cast[cstring](addr tokens[1][0]), size) or size < I64(0):
      return AsmInvalidImmediate
    var i = I64(0)
    while i < size:
      if not appendByte(U8(0)):
        return AsmSectionOverflow
      inc i
    return AsmOk

  if tokenIs(tokens[0], cstring(".byte")) and count >= U32(2):
    var i = U32(1)
    while i < count:
      var value = I64(0)
      if not parseInteger(cast[cstring](addr tokens[i][0]), value) or
          value < I64(-128) or value > I64(255):
        return AsmInvalidImmediate
      if not appendByte(U8(value and I64(0xff))):
        return AsmSectionOverflow
      inc i
    return AsmOk

  if tokenIs(tokens[0], cstring(".asciz")):
    var pos = 0
    while line[pos] != '\0' and line[pos] != '"':
      inc pos
    if line[pos] != '"':
      return AsmSyntaxError
    inc pos
    while line[pos] != '\0' and line[pos] != '"':
      var ch = line[pos]
      if ch == '\\':
        inc pos
        case line[pos]
        of 'n': ch = '\n'
        of 'r': ch = '\r'
        of 't': ch = '\t'
        of '0': ch = '\0'
        of '\\': ch = '\\'
        of '"': ch = '"'
        else: return AsmSyntaxError
      if not appendByte(U8(ord(ch))):
        return AsmSectionOverflow
      inc pos
    if line[pos] != '"':
      return AsmSyntaxError
    if not appendByte(U8(0)):
      return AsmSectionOverflow
    return AsmOk

  AsmUnknownDirective


## Parses one source line and updates labels, sections, directives, or emitted text.
proc parseLine(line: cstring): AsmStatus =
  var tokens: array[TokenCapacity, array[TokenLength, char]]
  var count = U32(0)
  if not tokenize(line, tokens, count):
    return AsmSyntaxError
  if count == U32(0):
    return AsmOk

  let first = cast[cstring](addr tokens[0][0])
  var firstLen = 0
  while first[firstLen] != '\0':
    inc firstLen
  if firstLen > 0 and first[firstLen - 1] == ':':
    tokens[0][firstLen - 1] = '\0'
    if count != U32(1):
      return AsmSyntaxError
    return addLabel(cast[cstring](addr tokens[0][0]))

  if tokenIs(tokens[0], cstring(".text")) and count == U32(1):
    state.section = SectionText
    return AsmOk
  if tokenIs(tokens[0], cstring(".rodata")) and count == U32(1):
    state.section = SectionRodata
    return AsmOk
  if tokenIs(tokens[0], cstring(".data")) and count == U32(1):
    state.section = SectionData
    return AsmOk
  if tokenIs(tokens[0], cstring(".bss")) and count == U32(1):
    state.section = SectionBss
    return AsmOk
  if tokenIs(tokens[0], cstring(".entry")) and count == U32(2):
    if not copyName(state.entryName, cast[cstring](addr tokens[1][0])):
      return AsmSyntaxError
    state.hasEntry = true
    return AsmOk

  if first[0] == '.':
    return emitDataDirective(line, tokens, count)

  emitInstruction(tokens, count)


## Applies queued PC-relative instruction relocations after label collection.
proc applyRelocations(): AsmStatus =
  var i = U32(0)
  while i < state.relocationCount:
    let relocation = state.relocations[i]
    var target = U64(0)
    if not labelAddress(cast[cstring](addr state.relocations[i].name[0]), target):
      return AsmUnknownLabel

    let location = RkxWriterUserBase + U64(relocation.offset)
    let displacement = I64(target) - I64(location)
    var first, second = U32(0)
    case relocation.kind
    of RelocLa:
      if not encodeLa(relocation.rd, displacement, first, second) or
          not patchInstruction(relocation.offset, first) or
          not patchInstruction(relocation.offset + U32(4), second):
        return AsmRelocationRange
    of RelocBranch:
      if not encodeB(relocation.funct3, relocation.rs1, relocation.rs2,
                     displacement, first) or
          not patchInstruction(relocation.offset, first):
        return AsmRelocationRange
    of RelocJump:
      if not encodeJ(relocation.rd, displacement, first) or
          not patchInstruction(relocation.offset, first):
        return AsmRelocationRange
    inc i
  AsmOk


## Parses source text and returns an RKX writer image descriptor backed by assembler buffers.
proc assembleSource*(source: ptr UncheckedArray[char], size: U32,
                     image: var RkxImageInput): AsmStatus =
  state = AsmState()
  var line: array[LineCapacity, char]
  var position = U32(0)

  while position < size:
    var len = U32(0)
    while position < size and source[position] != '\n':
      if source[position] != '\r':
        if len + U32(1) >= U32(LineCapacity):
          return AsmLineTooLong
        line[len] = source[position]
        inc len
      inc position
    line[len] = '\0'
    if position < size and source[position] == '\n':
      inc position

    let status = parseLine(cast[cstring](addr line[0]))
    if status != AsmOk:
      return status

  if not state.hasEntry:
    return AsmMissingEntry

  var entry = U64(0)
  if not labelAddress(cast[cstring](addr state.entryName[0]), entry):
    return AsmUnknownLabel

  let relocationStatus = applyRelocations()
  if relocationStatus != AsmOk:
    return relocationStatus

  image = RkxImageInput(
    entryVa: entry,
    text: RkxSegmentInput(
      va: sectionBase(SectionText),
      data: addr state.text[0],
      fileSize: U64(state.textLen),
      memSize: U64(state.textLen),
    ),
    rodata: RkxSegmentInput(
      va: sectionBase(SectionRodata),
      data: addr state.rodata[0],
      fileSize: U64(state.rodataLen),
      memSize: U64(state.rodataLen),
    ),
    data: RkxSegmentInput(
      va: sectionBase(SectionData),
      data: addr state.data[0],
      fileSize: U64(state.dataLen),
      memSize: U64(state.dataLen),
    ),
    bssVa: sectionBase(SectionBss),
    bssMemSize: U64(state.bssLen),
    stackPages: U32(2),
  )

  if validateRkxImage(image) != RkxWriterOk:
    return AsmInvalidImage

  AsmOk


## Returns a printable diagnostic label for one assembler result.
proc asmStatusText*(status: AsmStatus): cstring =
  case status
  of AsmOk: cstring("ok")
  of AsmSourceTooLarge: cstring("source too large")
  of AsmLineTooLong: cstring("line too long")
  of AsmSyntaxError: cstring("syntax error")
  of AsmUnknownDirective: cstring("unknown directive")
  of AsmUnknownInstruction: cstring("unknown instruction")
  of AsmInvalidRegister: cstring("invalid register")
  of AsmInvalidImmediate: cstring("invalid immediate")
  of AsmWrongSection: cstring("wrong section")
  of AsmSectionOverflow: cstring("section too large")
  of AsmTooManyLabels: cstring("too many labels")
  of AsmDuplicateLabel: cstring("duplicate label")
  of AsmMissingEntry: cstring("missing entry")
  of AsmUnknownLabel: cstring("unknown label")
  of AsmTooManyRelocations: cstring("too many relocations")
  of AsmRelocationRange: cstring("relocation out of range")
  of AsmInvalidImage: cstring("invalid image layout")
