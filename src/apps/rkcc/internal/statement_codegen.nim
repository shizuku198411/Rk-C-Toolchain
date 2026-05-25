## Parses rkcc declarations and control-flow statements into assembly output.
from lib/syscall_ids import SysExit
from lib/types import I64, U32
import ./compiler_context
import ./expression_codegen
import ./source_tokens


## Parses a local variable declaration and emits its initial stack value.
proc parseDeclaration(parser: var Parser): CompileStatus =
  let isChar = parser.current.kind == TokenChar
  var kind = LocalInt
  var size = I64(8)
  var status = parser.advance()
  if status != CcOk:
    return status
  if isChar and parser.current.kind == TokenStar:
    kind = LocalCString
    status = parser.advance()
    if status != CcOk:
      return status
  if parser.current.kind != TokenIdentifier:
    return CcSyntaxError

  var identifier = parser.current
  status = parser.advance()
  if status != CcOk:
    return status

  if isChar and kind != LocalCString:
    if parser.current.kind != TokenLeftBracket:
      return CcUnsupported
    status = parser.advance()
    if status != CcOk:
      return status
    if parser.current.kind != TokenInteger or parser.current.value <= I64(0):
      return CcUnsupported
    size = parser.current.value
    kind = LocalBuffer
    status = parser.advance()
    if status != CcOk:
      return status
    status = parser.expect(TokenRightBracket)
    if status != CcOk:
      return status

  var index = U32(0)
  status = parser.addLocal(
    identifier,
    kind,
    size,
    index,
  )
  if status != CcOk:
    return status

  if parser.current.kind == TokenAssign:
    status = parser.advance()
    if status != CcOk:
      return status
    if kind == LocalBuffer:
      return CcUnsupported
    if kind == LocalCString:
      if parser.current.kind != TokenString:
        return CcUnsupported
      var label = U32(0)
      parser.locals[index].stringLen = parser.current.stringLen
      status = parser.addStringLiteral(parser.current, label)
      if status != CcOk:
        return status
      status = parser.advance()
      if status != CcOk:
        return status
      if not emitLabelText(parser.text, cstring("  la a0, .Lcc"), label,
                           cstring("\n")):
        return CcOutputTooLarge
    else:
      status = parser.parseExpression()
      if status != CcOk:
        return status
  elif kind == LocalCString:
    return CcUnsupported
  elif kind == LocalInt and not emitLine(parser.text, cstring("  li a0, 0")):
    return CcOutputTooLarge

  status = parser.expect(TokenSemicolon)
  if status != CcOk:
    return status
  if kind == LocalBuffer:
    return CcOk
  parser.emitStoreLocal(parser.locals[index].offset)


## Parses an assignment to an already declared local value.
proc parseAssignment(parser: var Parser, identifier: var Token): CompileStatus =
  var index = U32(0)
  if not parser.lookupLocal(identifier, index):
    return CcUnknownIdentifier
  if parser.locals[index].kind == LocalBuffer:
    return CcUnsupported
  var status = parser.expect(TokenAssign)
  if status != CcOk:
    return status
  if parser.locals[index].kind == LocalCString:
    if parser.current.kind != TokenString:
      return CcUnsupported
    var label = U32(0)
    parser.locals[index].stringLen = parser.current.stringLen
    status = parser.addStringLiteral(parser.current, label)
    if status != CcOk:
      return status
    status = parser.advance()
    if status != CcOk:
      return status
    if not emitLabelText(parser.text, cstring("  la a0, .Lcc"), label,
                         cstring("\n")):
      return CcOutputTooLarge
  else:
    status = parser.parseExpression()
    if status != CcOk:
      return status
  status = parser.expect(TokenSemicolon)
  if status != CcOk:
    return status
  parser.emitStoreLocal(parser.locals[index].offset)


## Parses one statement or nested compound block.
proc parseStatement*(parser: var Parser): CompileStatus


## Parses a compound statement block.
proc parseBlock*(parser: var Parser): CompileStatus =
  var status = parser.expect(TokenLeftBrace)
  if status != CcOk:
    return status
  while parser.current.kind != TokenRightBrace:
    if parser.current.kind == TokenEof:
      return CcSyntaxError
    status = parser.parseStatement()
    if status != CcOk:
      return status
  parser.expect(TokenRightBrace)


## Parses an if/else statement and emits zero-tested control flow.
proc parseIf(parser: var Parser): CompileStatus =
  var status = parser.advance()
  if status != CcOk:
    return status
  status = parser.expect(TokenLeftParen)
  if status != CcOk:
    return status
  status = parser.parseExpression()
  if status != CcOk:
    return status
  status = parser.expect(TokenRightParen)
  if status != CcOk:
    return status
  let elseLabel = parser.allocateLabel()
  let doneLabel = parser.allocateLabel()
  if not emitLine(parser.text, cstring("  li t0, 0")) or
      not emitLabelText(parser.text, cstring("  beq a0, t0, .Lcc"),
                        elseLabel, cstring("\n")):
    return CcOutputTooLarge
  status = parser.parseStatement()
  if status != CcOk:
    return status
  if not emitLabelText(parser.text, cstring("  j .Lcc"), doneLabel,
                       cstring("\n")) or
      not emitLabelText(parser.text, cstring(".Lcc"), elseLabel,
                        cstring(":\n")):
    return CcOutputTooLarge
  if parser.current.kind == TokenElse:
    status = parser.advance()
    if status != CcOk:
      return status
    status = parser.parseStatement()
    if status != CcOk:
      return status
  if not emitLabelText(parser.text, cstring(".Lcc"), doneLabel,
                       cstring(":\n")):
    return CcOutputTooLarge
  CcOk


## Parses a while loop and emits a backward branch through generated labels.
proc parseWhile(parser: var Parser): CompileStatus =
  let startLabel = parser.allocateLabel()
  let doneLabel = parser.allocateLabel()
  if not emitLabelText(parser.text, cstring(".Lcc"), startLabel,
                       cstring(":\n")):
    return CcOutputTooLarge
  var status = parser.advance()
  if status != CcOk:
    return status
  status = parser.expect(TokenLeftParen)
  if status != CcOk:
    return status
  status = parser.parseExpression()
  if status != CcOk:
    return status
  status = parser.expect(TokenRightParen)
  if status != CcOk:
    return status
  if not emitLine(parser.text, cstring("  li t0, 0")) or
      not emitLabelText(parser.text, cstring("  beq a0, t0, .Lcc"),
                        doneLabel, cstring("\n")):
    return CcOutputTooLarge
  status = parser.parseStatement()
  if status != CcOk:
    return status
  if not emitLabelText(parser.text, cstring("  j .Lcc"), startLabel,
                       cstring("\n")) or
      not emitLabelText(parser.text, cstring(".Lcc"), doneLabel,
                        cstring(":\n")):
    return CcOutputTooLarge
  CcOk


## Parses return, declarations, calls, assignment, conditionals, and loops.
proc parseStatement*(parser: var Parser): CompileStatus =
  if parser.current.kind == TokenLeftBrace:
    return parser.parseBlock()
  if parser.current.kind == TokenInt or parser.current.kind == TokenChar:
    return parser.parseDeclaration()
  if parser.current.kind == TokenIf:
    return parser.parseIf()
  if parser.current.kind == TokenWhile:
    return parser.parseWhile()
  if parser.current.kind == TokenReturn:
    var status = parser.advance()
    if status != CcOk:
      return status
    status = parser.parseExpression()
    if status != CcOk:
      return status
    status = parser.expect(TokenSemicolon)
    if status != CcOk:
      return status
    status = parser.emitSyscall(I64(SysExit))
    if status != CcOk:
      return status
    parser.sawReturn = true
    return CcOk
  if parser.current.kind != TokenIdentifier:
    return CcSyntaxError

  var identifier = parser.current
  var status = parser.advance()
  if status != CcOk:
    return status
  if parser.current.kind == TokenLeftParen:
    status = parser.parseBuiltinCall(identifier)
    if status != CcOk:
      return status
    return parser.expect(TokenSemicolon)
  if parser.current.kind == TokenAssign:
    return parser.parseAssignment(identifier)
  CcSyntaxError
