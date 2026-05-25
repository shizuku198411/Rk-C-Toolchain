## Coordinates rkcc translation-unit compilation and exposes diagnostics to the app.
from lib/syscall_ids import SysExit
from lib/types import I64, U32
import ./asm_output
import ./compiler_context
import ./source_tokens
import ./statement_codegen

export compiler_context


## Compiles one `int main()` translation unit into bounded rkas source text.
proc compileSource*(source: ptr UncheckedArray[char], size: U32,
                    output: var AsmOutput,
                    useStdlib: bool = false): CompileStatus =
  var parser: Parser
  parser.lexer.initLexer(source, size)
  parser.text.initAsmOutput()
  parser.rodata.initAsmOutput()
  parser.useStdlib = useStdlib

  if not parser.text.emitLine(cstring(".text")) or
      not parser.text.emitLine(cstring(".entry _start")) or
      not parser.text.emitLine(cstring("_start:")) or
      not emitNumberLine(parser.text, cstring("  addi sp, sp, -"),
                         I64(StackFrameSize)):
    return CcOutputTooLarge

  var status = parser.advance()
  if status != CcOk:
    return status
  status = parser.expect(TokenInt)
  if status != CcOk or parser.current.kind != TokenIdentifier or
      parser.current.text[0] != 'm' or parser.current.text[1] != 'a' or
      parser.current.text[2] != 'i' or parser.current.text[3] != 'n' or
      parser.current.text[4] != '\0':
    return CcSyntaxError
  status = parser.advance()
  if status != CcOk:
    return status
  status = parser.expect(TokenLeftParen)
  if status != CcOk:
    return status
  status = parser.expect(TokenRightParen)
  if status != CcOk:
    return status
  status = parser.parseBlock()
  if status != CcOk:
    return status
  if parser.current.kind != TokenEof:
    return CcSyntaxError

  if not parser.sawReturn:
    if not emitLine(parser.text, cstring("  li a0, 0")):
      return CcOutputTooLarge
    if useStdlib:
      if parser.emitCall(cstring("exit")) != CcOk:
        return CcOutputTooLarge
    elif not emitNumberLine(parser.text, cstring("  li a3, "), I64(SysExit)) or
        not emitLine(parser.text, cstring("  ecall")):
      return CcOutputTooLarge
  if not emitLine(parser.text, cstring(".rodata")) or
      not parser.text.appendText(cast[cstring](addr parser.rodata.data[0])) or
      not emitLine(parser.text, cstring(".data")) or
      not emitLine(parser.text, cstring(".bss")):
    return CcOutputTooLarge

  output = parser.text
  CcOk


## Returns a stable user-facing description of one compilation status.
proc compileStatusText*(status: CompileStatus): cstring =
  case status
  of CcOk: cstring("ok")
  of CcLexError: cstring("invalid token or string literal")
  of CcSyntaxError: cstring("syntax error")
  of CcUnsupported: cstring("unsupported language construct")
  of CcUnknownIdentifier: cstring("unknown identifier")
  of CcDuplicateIdentifier: cstring("duplicate local variable")
  of CcTooManyLocals: cstring("too many local variables")
  of CcExpressionTooDeep: cstring("expression nesting too deep")
  of CcOutputTooLarge: cstring("generated assembly too large")
