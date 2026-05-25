## Parses rkcc integer expressions and lowers libc-mini builtin calls.
from lib/syscall_ids import SysClose, SysExit, SysGetGid, SysGetUid, SysOpen,
  SysReadFd, SysWriteFd
from lib/types import I64, U32
import ./compiler_context
import ./source_tokens


## Emits one string or writable-buffer address and optionally returns known length.
proc parsePointerArgument(parser: var Parser, writableOnly: bool,
                          length: var U32, knownLength: var bool): CompileStatus =
  knownLength = false
  if parser.current.kind == TokenString:
    if writableOnly:
      return CcUnsupported
    var label = U32(0)
    length = parser.current.stringLen
    knownLength = true
    var status = parser.addStringLiteral(parser.current, label)
    if status != CcOk:
      return status
    status = parser.advance()
    if status != CcOk:
      return status
    if not emitLabelText(parser.text, cstring("  la a0, .Lcc"), label,
                         cstring("\n")):
      return CcOutputTooLarge
    return CcOk

  if parser.current.kind != TokenIdentifier:
    return CcUnsupported
  var index = U32(0)
  if not parser.lookupLocal(parser.current, index):
    return CcUnknownIdentifier
  if writableOnly and parser.locals[index].kind != LocalBuffer:
    return CcUnsupported
  let kind = parser.locals[index].kind
  let offset = parser.locals[index].offset
  if kind == LocalCString:
    length = parser.locals[index].stringLen
    knownLength = true
  elif kind != LocalBuffer:
    return CcUnsupported
  var status = parser.advance()
  if status != CcOk:
    return status
  if kind == LocalBuffer:
    if not emitNumberLine(parser.text, cstring("  addi a0, sp, "), offset):
      return CcOutputTooLarge
  elif not emitNumberLine(parser.text, cstring("  ld a0, "), offset,
                          cstring("(sp)")):
    return CcOutputTooLarge
  CcOk


## Parses a libc-mini builtin call whose opening parenthesis is current.
proc parseBuiltinCall*(parser: var Parser, identifier: var Token): CompileStatus


## Emits a full integer expression through bitwise-or precedence.
proc parseExpression*(parser: var Parser): CompileStatus


## Emits a primary integer expression into a0.
proc parsePrimary(parser: var Parser): CompileStatus =
  if parser.current.kind == TokenInteger:
    let value = parser.current.value
    let status = parser.advance()
    if status != CcOk:
      return status
    if not emitNumberLine(parser.text, cstring("  li a0, "), value):
      return CcOutputTooLarge
    return CcOk

  if parser.current.kind == TokenIdentifier:
    var identifier = parser.current
    var status = parser.advance()
    if status != CcOk:
      return status
    if parser.current.kind == TokenLeftParen:
      return parser.parseBuiltinCall(identifier)
    var index = U32(0)
    if not parser.lookupLocal(identifier, index) or
        parser.locals[index].kind != LocalInt:
      return CcUnknownIdentifier
    let offset = parser.locals[index].offset
    if not emitNumberLine(parser.text, cstring("  ld a0, "), offset,
                          cstring("(sp)")):
      return CcOutputTooLarge
    return CcOk

  if parser.current.kind == TokenLeftParen:
    var status = parser.advance()
    if status != CcOk:
      return status
    status = parser.parseExpression()
    if status != CcOk:
      return status
    return parser.expect(TokenRightParen)

  if parser.current.kind == TokenMinus:
    var status = parser.advance()
    if status != CcOk:
      return status
    status = parser.parsePrimary()
    if status != CcOk:
      return status
    if not emitLine(parser.text, cstring("  sub a0, zero, a0")):
      return CcOutputTooLarge
    return CcOk

  CcSyntaxError


## Spills one binary operation left operand and reserves its scratch slot.
proc spillLeftOperand(parser: var Parser, offset: var I64): CompileStatus =
  if parser.scratchDepth >= U32(ScratchCapacity):
    return CcExpressionTooDeep
  offset = I64(ScratchBase) + I64(parser.scratchDepth) * I64(8)
  inc parser.scratchDepth
  if not emitNumberLine(parser.text, cstring("  sd a0, "), offset,
                        cstring("(sp)")):
    return CcOutputTooLarge
  CcOk


## Restores one binary operation left operand to t0 after its right operand.
proc reloadLeftOperand(parser: var Parser, offset: I64): CompileStatus =
  dec parser.scratchDepth
  if not emitNumberLine(parser.text, cstring("  ld t0, "), offset,
                        cstring("(sp)")):
    return CcOutputTooLarge
  CcOk


## Emits multiplicative integer operations using the RV64M assembler subset.
proc parseMultiplicative(parser: var Parser): CompileStatus =
  var status = parser.parsePrimary()
  if status != CcOk:
    return status

  while parser.current.kind == TokenStar or parser.current.kind == TokenSlash or
      parser.current.kind == TokenPercent:
    let operation = parser.current.kind
    var offset = I64(0)
    status = parser.spillLeftOperand(offset)
    if status != CcOk:
      return status
    status = parser.advance()
    if status != CcOk:
      return status
    status = parser.parsePrimary()
    if status != CcOk:
      return status
    status = parser.reloadLeftOperand(offset)
    if status != CcOk:
      return status
    let instruction =
      if operation == TokenStar: cstring("  mul a0, t0, a0")
      elif operation == TokenSlash: cstring("  div a0, t0, a0")
      else: cstring("  rem a0, t0, a0")
    if not emitLine(parser.text, instruction):
      return CcOutputTooLarge
  CcOk


## Emits additive integer expressions using temporary stack spill slots.
proc parseAdditive(parser: var Parser): CompileStatus =
  var status = parser.parseMultiplicative()
  if status != CcOk:
    return status

  while parser.current.kind == TokenPlus or parser.current.kind == TokenMinus:
    let operation = parser.current.kind
    var offset = I64(0)
    status = parser.spillLeftOperand(offset)
    if status != CcOk:
      return status
    status = parser.advance()
    if status != CcOk:
      return status
    status = parser.parseMultiplicative()
    if status != CcOk:
      return status
    status = parser.reloadLeftOperand(offset)
    if status != CcOk:
      return status
    if not emitLine(parser.text,
        if operation == TokenPlus: cstring("  add a0, t0, a0")
        else: cstring("  sub a0, t0, a0")):
      return CcOutputTooLarge
  CcOk


## Emits integer shifts whose result is kept in a0.
proc parseShift(parser: var Parser): CompileStatus =
  var status = parser.parseAdditive()
  if status != CcOk:
    return status

  while parser.current.kind == TokenShiftLeft or
      parser.current.kind == TokenShiftRight:
    let operation = parser.current.kind
    var offset = I64(0)
    status = parser.spillLeftOperand(offset)
    if status != CcOk:
      return status
    status = parser.advance()
    if status != CcOk:
      return status
    status = parser.parseAdditive()
    if status != CcOk:
      return status
    status = parser.reloadLeftOperand(offset)
    if status != CcOk:
      return status
    if not emitLine(parser.text,
        if operation == TokenShiftLeft: cstring("  sll a0, t0, a0")
        else: cstring("  sra a0, t0, a0")):
      return CcOutputTooLarge
  CcOk


## Emits signed relational comparisons as integer zero or one values.
proc parseRelational(parser: var Parser): CompileStatus =
  var status = parser.parseShift()
  if status != CcOk:
    return status

  while parser.current.kind == TokenLess or parser.current.kind == TokenLessEqual or
      parser.current.kind == TokenGreater or parser.current.kind == TokenGreaterEqual:
    let operation = parser.current.kind
    var offset = I64(0)
    status = parser.spillLeftOperand(offset)
    if status != CcOk:
      return status
    status = parser.advance()
    if status != CcOk:
      return status
    status = parser.parseShift()
    if status != CcOk:
      return status
    status = parser.reloadLeftOperand(offset)
    if status != CcOk:
      return status
    let instruction =
      if operation == TokenLess or operation == TokenGreaterEqual:
        cstring("  slt a0, t0, a0")
      else:
        cstring("  slt a0, a0, t0")
    if not emitLine(parser.text, instruction):
      return CcOutputTooLarge
    if (operation == TokenLessEqual or operation == TokenGreaterEqual) and
        not emitLine(parser.text, cstring("  xori a0, a0, 1")):
      return CcOutputTooLarge
  CcOk


## Emits equality and inequality expressions as integer zero or one values.
proc parseEquality(parser: var Parser): CompileStatus =
  var status = parser.parseRelational()
  if status != CcOk:
    return status
  while parser.current.kind == TokenEqual or parser.current.kind == TokenNotEqual:
    let operation = parser.current.kind
    var offset = I64(0)
    status = parser.spillLeftOperand(offset)
    if status != CcOk:
      return status
    status = parser.advance()
    if status != CcOk:
      return status
    status = parser.parseRelational()
    if status != CcOk:
      return status
    status = parser.reloadLeftOperand(offset)
    if status != CcOk:
      return status
    let trueLabel = parser.allocateLabel()
    let doneLabel = parser.allocateLabel()
    if not emitLabelText(parser.text,
          if operation == TokenEqual: cstring("  beq t0, a0, .Lcc")
          else: cstring("  bne t0, a0, .Lcc"), trueLabel, cstring("\n")) or
        not emitLine(parser.text, cstring("  li a0, 0")) or
        not emitLabelText(parser.text, cstring("  j .Lcc"), doneLabel,
                          cstring("\n")) or
        not emitLabelText(parser.text, cstring(".Lcc"), trueLabel,
                          cstring(":\n")) or
        not emitLine(parser.text, cstring("  li a0, 1")) or
        not emitLabelText(parser.text, cstring(".Lcc"), doneLabel,
                          cstring(":\n")):
      return CcOutputTooLarge
  CcOk


## Emits one binary bitwise precedence level.
proc parseBitwiseLevel(parser: var Parser, operation: TokenKind): CompileStatus =
  var status =
    if operation == TokenAmpersand: parser.parseEquality()
    elif operation == TokenCaret: parser.parseBitwiseLevel(TokenAmpersand)
    else: parser.parseBitwiseLevel(TokenCaret)
  if status != CcOk:
    return status

  while parser.current.kind == operation:
    var offset = I64(0)
    status = parser.spillLeftOperand(offset)
    if status != CcOk:
      return status
    status = parser.advance()
    if status != CcOk:
      return status
    status =
      if operation == TokenAmpersand: parser.parseEquality()
      elif operation == TokenCaret: parser.parseBitwiseLevel(TokenAmpersand)
      else: parser.parseBitwiseLevel(TokenCaret)
    if status != CcOk:
      return status
    status = parser.reloadLeftOperand(offset)
    if status != CcOk:
      return status
    let instruction =
      if operation == TokenAmpersand: cstring("  and a0, t0, a0")
      elif operation == TokenCaret: cstring("  xor a0, t0, a0")
      else: cstring("  or a0, t0, a0")
    if not emitLine(parser.text, instruction):
      return CcOutputTooLarge
  CcOk


## Emits a full integer expression through bitwise-or precedence.
proc parseExpression*(parser: var Parser): CompileStatus =
  parser.parseBitwiseLevel(TokenPipe)


## Parses one libc-mini builtin call and leaves its return value in a0.
proc parseBuiltinCall*(parser: var Parser, identifier: var Token): CompileStatus =
  var status = parser.expect(TokenLeftParen)
  if status != CcOk:
    return status

  if identifier.tokenIsName(cstring("getuid")) or
      identifier.tokenIsName(cstring("getgid")):
    status = parser.expect(TokenRightParen)
    if status != CcOk:
      return status
    return parser.emitSyscall(
      if identifier.tokenIsName(cstring("getuid")): I64(SysGetUid)
      else: I64(SysGetGid))

  var length = U32(0)
  var knownLength = false

  if identifier.tokenIsName(cstring("puts")):
    status = parser.parsePointerArgument(false, length, knownLength)
    if status != CcOk:
      return status
    if parser.useStdlib:
      status = parser.expect(TokenRightParen)
      if status != CcOk:
        return status
      return parser.emitCall(cstring("puts"))
    if not knownLength:
      return CcUnsupported
    status = parser.storeCallArg(I64(1))
    if status != CcOk:
      return status
    status = parser.expect(TokenRightParen)
    if status != CcOk:
      return status
    if not emitLine(parser.text, cstring("  li a0, 1")):
      return CcOutputTooLarge
    status = parser.loadCallArg(I64(1))
    if status != CcOk:
      return status
    if not emitNumberLine(parser.text, cstring("  li a2, "), I64(length)):
      return CcOutputTooLarge
    return parser.emitSyscall(I64(SysWriteFd))

  if identifier.tokenIsName(cstring("strlen")):
    status = parser.parsePointerArgument(false, length, knownLength)
    if status != CcOk:
      return status
    if parser.useStdlib:
      status = parser.expect(TokenRightParen)
      if status != CcOk:
        return status
      return parser.emitCall(cstring("strlen"))
    if not knownLength:
      return CcUnsupported
    status = parser.expect(TokenRightParen)
    if status != CcOk:
      return status
    if not emitNumberLine(parser.text, cstring("  li a0, "), I64(length)):
      return CcOutputTooLarge
    return CcOk

  if identifier.tokenIsName(cstring("open")):
    status = parser.parsePointerArgument(false, length, knownLength)
    if status != CcOk:
      return status
    status = parser.storeCallArg(I64(0))
    if status != CcOk:
      return status
    status = parser.expect(TokenComma)
    if status != CcOk:
      return status
    status = parser.parseExpression()
    if status != CcOk:
      return status
    status = parser.storeCallArg(I64(1))
    if status != CcOk:
      return status
    status = parser.expect(TokenRightParen)
    if status != CcOk:
      return status
    status = parser.loadCallArg(I64(0))
    if status != CcOk:
      return status
    status = parser.loadCallArg(I64(1))
    if status != CcOk:
      return status
    return parser.emitSyscall(I64(SysOpen))

  if identifier.tokenIsName(cstring("close")):
    status = parser.parseExpression()
    if status != CcOk:
      return status
    status = parser.expect(TokenRightParen)
    if status != CcOk:
      return status
    return parser.emitSyscall(I64(SysClose))

  if identifier.tokenIsName(cstring("write")) or
      identifier.tokenIsName(cstring("read")):
    status = parser.parseExpression()
    if status != CcOk:
      return status
    status = parser.storeCallArg(I64(0))
    if status != CcOk:
      return status
    status = parser.expect(TokenComma)
    if status != CcOk:
      return status
    status = parser.parsePointerArgument(
      identifier.tokenIsName(cstring("read")), length, knownLength)
    if status != CcOk:
      return status
    status = parser.storeCallArg(I64(1))
    if status != CcOk:
      return status
    status = parser.expect(TokenComma)
    if status != CcOk:
      return status
    status = parser.parseExpression()
    if status != CcOk:
      return status
    status = parser.storeCallArg(I64(2))
    if status != CcOk:
      return status
    status = parser.expect(TokenRightParen)
    if status != CcOk:
      return status
    status = parser.loadCallArg(I64(0))
    if status != CcOk:
      return status
    status = parser.loadCallArg(I64(1))
    if status != CcOk:
      return status
    status = parser.loadCallArg(I64(2))
    if status != CcOk:
      return status
    if parser.useStdlib and identifier.tokenIsName(cstring("write")):
      return parser.emitCall(cstring("write"))
    return parser.emitSyscall(
      if identifier.tokenIsName(cstring("read")): I64(SysReadFd)
      else: I64(SysWriteFd))

  if identifier.tokenIsName(cstring("exit")):
    status = parser.parseExpression()
    if status != CcOk:
      return status
    status = parser.expect(TokenRightParen)
    if status != CcOk:
      return status
    parser.sawReturn = true
    if parser.useStdlib:
      return parser.emitCall(cstring("exit"))
    return parser.emitSyscall(I64(SysExit))

  CcUnsupported
