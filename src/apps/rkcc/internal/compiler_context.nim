## Holds shared rkcc parser state, local storage metadata, and assembly emit helpers.
from lib/types import I64, U32
import ./asm_output
import ./source_tokens


const
  LocalCapacity* = 16
  ScratchCapacity* = 8
  StackFrameSize* = 512
  LocalStorageLimit* = 256
  ScratchBase* = 256
  CallArgBase* = 352


type
  CompileStatus* = enum
    CcOk,
    CcLexError,
    CcSyntaxError,
    CcUnsupported,
    CcUnknownIdentifier,
    CcDuplicateIdentifier,
    CcTooManyLocals,
    CcExpressionTooDeep,
    CcOutputTooLarge

  LocalKind* = enum
    LocalInt,
    LocalCString,
    LocalBuffer

  Local* = object
    name*: array[TokenTextCapacity, char]
    kind*: LocalKind
    offset*: I64
    stringLen*: U32

  Parser* = object
    lexer*: Lexer
    current*: Token
    text*: AsmOutput
    rodata*: AsmOutput
    locals*: array[LocalCapacity, Local]
    localCount*: U32
    nextLocalOffset*: I64
    nextLabel*: U32
    scratchDepth*: U32
    sawReturn*: bool
    useStdlib*: bool


## Copies one identifier token into stable local storage.
proc copyName(dst: var array[TokenTextCapacity, char],
              src: var array[TokenTextCapacity, char]) =
  var pos = U32(0)
  while pos + U32(1) < U32(TokenTextCapacity) and src[pos] != '\0':
    dst[pos] = src[pos]
    inc pos
  dst[pos] = '\0'


## Tests two bounded identifier buffers for exact equality.
proc sameName(left, right: var array[TokenTextCapacity, char]): bool =
  var pos = U32(0)
  while left[pos] != '\0' and right[pos] != '\0':
    if left[pos] != right[pos]:
      return false
    inc pos
  left[pos] == '\0' and right[pos] == '\0'


## Advances one token and normalizes any lexer error into a compiler error.
proc advance*(parser: var Parser): CompileStatus =
  if parser.lexer.nextToken(parser.current) != LexOk:
    return CcLexError
  CcOk


## Consumes a required punctuation or keyword token.
proc expect*(parser: var Parser, kind: TokenKind): CompileStatus =
  if parser.current.kind != kind:
    return CcSyntaxError
  parser.advance()


## Emits a complete assembly line with one static text fragment.
proc emitLine*(output: var AsmOutput, text: cstring): bool =
  output.appendText(text) and output.appendNewline()


## Emits an instruction with a signed numeric operand.
proc emitNumberLine*(output: var AsmOutput, prefix: cstring, value: I64,
                     suffix: cstring = cstring("")): bool =
  output.appendText(prefix) and output.appendNumber(value) and
    output.appendText(suffix) and output.appendNewline()


## Allocates a unique internal assembly label number.
proc allocateLabel*(parser: var Parser): U32 =
  result = parser.nextLabel
  inc parser.nextLabel


## Emits the definition or use prefix of one internal label.
proc emitLabelText*(output: var AsmOutput, prefix: cstring, label: U32,
                    suffix: cstring): bool =
  output.appendText(prefix) and output.appendNumber(I64(label)) and
    output.appendText(suffix)


## Looks up one declared local variable by source identifier.
proc lookupLocal*(parser: var Parser, token: var Token, index: var U32): bool =
  var pos = U32(0)
  while pos < parser.localCount:
    if sameName(parser.locals[pos].name, token.text):
      index = pos
      return true
    inc pos
  false


## Creates a local stack slot and rejects duplicate or excessive declarations.
proc addLocal*(parser: var Parser, token: var Token, kind: LocalKind,
               size: I64, index: var U32): CompileStatus =
  if parser.lookupLocal(token, index):
    return CcDuplicateIdentifier
  if parser.localCount >= U32(LocalCapacity):
    return CcTooManyLocals

  index = parser.localCount
  let alignedSize = ((size + I64(7)) div I64(8)) * I64(8)
  if size <= I64(0) or parser.nextLocalOffset + alignedSize > I64(LocalStorageLimit):
    return CcTooManyLocals
  copyName(parser.locals[index].name, token.text)
  parser.locals[index].kind = kind
  parser.locals[index].offset = parser.nextLocalOffset
  parser.locals[index].stringLen = U32(0)
  parser.nextLocalOffset = parser.nextLocalOffset + alignedSize
  inc parser.localCount
  CcOk


## Emits a stack store of the expression result held in a0.
proc emitStoreLocal*(parser: var Parser, offset: I64): CompileStatus =
  if not emitNumberLine(parser.text, cstring("  sd a0, "), offset,
                        cstring("(sp)")):
    return CcOutputTooLarge
  CcOk


## Adds one string literal to rodata and returns its label number.
proc addStringLiteral*(parser: var Parser, token: var Token,
                       label: var U32): CompileStatus =
  label = parser.allocateLabel()
  if not emitLabelText(parser.rodata, cstring(".Lcc"), label, cstring(":\n")) or
      not parser.rodata.appendText(cstring("  .asciz \"")) or
      not parser.rodata.appendText(cast[cstring](addr token.text[0])) or
      not parser.rodata.appendText(cstring("\"\n")):
    return CcOutputTooLarge
  CcOk


## Tests an identifier token against one compiler-known name.
proc tokenIsName*(token: var Token, name: cstring): bool =
  var pos = U32(0)
  while token.text[pos] != '\0' and name[pos] != '\0':
    if token.text[pos] != name[pos]:
      return false
    inc pos
  token.text[pos] == '\0' and name[pos] == '\0'


## Emits one syscall while keeping its result in a0.
proc emitSyscall*(parser: var Parser, number: I64): CompileStatus =
  if not emitNumberLine(parser.text, cstring("  li a3, "), number) or
      not emitLine(parser.text, cstring("  ecall")):
    return CcOutputTooLarge
  CcOk


## Emits a linker-resolved call to one userspace library routine.
proc emitCall*(parser: var Parser, name: cstring): CompileStatus =
  if not parser.text.appendText(cstring("  call ")) or
      not parser.text.appendText(name) or
      not parser.text.appendNewline():
    return CcOutputTooLarge
  CcOk


## Stores the current expression result for later syscall argument loading.
proc storeCallArg*(parser: var Parser, index: I64): CompileStatus =
  if not emitNumberLine(parser.text, cstring("  sd a0, "),
                        I64(CallArgBase) + index * I64(8),
                        cstring("(sp)")):
    return CcOutputTooLarge
  CcOk


## Loads a stored syscall argument into one ABI argument register.
proc loadCallArg*(parser: var Parser, index: I64): CompileStatus =
  let prefix =
    if index == I64(0): cstring("  ld a0, ")
    elif index == I64(1): cstring("  ld a1, ")
    else: cstring("  ld a2, ")
  if not emitNumberLine(parser.text, prefix,
                        I64(CallArgBase) + index * I64(8),
                        cstring("(sp)")):
    return CcOutputTooLarge
  CcOk
