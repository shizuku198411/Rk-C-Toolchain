## Tokenizes the initial rkcc C-like source language without dynamic allocation.
from lib/types import I64, U32


const
  TokenTextCapacity* = 96


type
  TokenKind* = enum
    TokenEof,
    TokenIdentifier,
    TokenInteger,
    TokenString,
    TokenInt,
    TokenChar,
    TokenIf,
    TokenElse,
    TokenWhile,
    TokenReturn,
    TokenLeftParen,
    TokenRightParen,
    TokenLeftBrace,
    TokenRightBrace,
    TokenLeftBracket,
    TokenRightBracket,
    TokenSemicolon,
    TokenAssign,
    TokenEqual,
    TokenNotEqual,
    TokenPlus,
    TokenMinus,
    TokenStar,
    TokenSlash,
    TokenPercent,
    TokenAmpersand,
    TokenPipe,
    TokenCaret,
    TokenShiftLeft,
    TokenShiftRight,
    TokenLess,
    TokenLessEqual,
    TokenGreater,
    TokenGreaterEqual,
    TokenComma

  LexStatus* = enum
    LexOk,
    LexUnexpectedCharacter,
    LexInvalidInteger,
    LexInvalidString,
    LexTokenTooLong

  Token* = object
    kind*: TokenKind
    text*: array[TokenTextCapacity, char]
    value*: I64
    stringLen*: U32

  Lexer* = object
    source: ptr UncheckedArray[char]
    size: U32
    pos: U32


## Initializes tokenization over a bounded source buffer.
proc initLexer*(lexer: var Lexer, source: ptr UncheckedArray[char], size: U32) =
  lexer.source = source
  lexer.size = size
  lexer.pos = U32(0)


## Returns whether a source character may begin an identifier.
proc isIdentifierStart(ch: char): bool =
  (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_'


## Returns whether a source character may continue an identifier.
proc isIdentifierPart(ch: char): bool =
  isIdentifierStart(ch) or (ch >= '0' and ch <= '9')


## Compares a token text buffer against one language keyword.
proc textIs(token: var Token, keyword: cstring): bool =
  var pos = U32(0)
  while token.text[pos] != '\0' and keyword[pos] != '\0':
    if token.text[pos] != keyword[pos]:
      return false
    inc pos
  token.text[pos] == '\0' and keyword[pos] == '\0'


## Skips whitespace and line comments before the next token.
proc skipIgnored(lexer: var Lexer) =
  while lexer.pos < lexer.size:
    let ch = lexer.source[lexer.pos]
    if ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n':
      inc lexer.pos
    elif ch == '/' and lexer.pos + U32(1) < lexer.size and
        lexer.source[lexer.pos + U32(1)] == '/':
      lexer.pos = lexer.pos + U32(2)
      while lexer.pos < lexer.size and lexer.source[lexer.pos] != '\n':
        inc lexer.pos
    else:
      break


## Parses one identifier and maps reserved words to keyword token kinds.
proc readIdentifier(lexer: var Lexer, token: var Token): LexStatus =
  var len = U32(0)
  while lexer.pos < lexer.size and isIdentifierPart(lexer.source[lexer.pos]):
    if len + U32(1) >= U32(TokenTextCapacity):
      return LexTokenTooLong
    token.text[len] = lexer.source[lexer.pos]
    inc len
    inc lexer.pos
  token.text[len] = '\0'
  token.kind =
    if token.textIs(cstring("int")): TokenInt
    elif token.textIs(cstring("char")): TokenChar
    elif token.textIs(cstring("if")): TokenIf
    elif token.textIs(cstring("else")): TokenElse
    elif token.textIs(cstring("while")): TokenWhile
    elif token.textIs(cstring("return")): TokenReturn
    else: TokenIdentifier
  LexOk


## Parses one decimal integer literal.
proc readInteger(lexer: var Lexer, token: var Token): LexStatus =
  var value = I64(0)
  while lexer.pos < lexer.size and lexer.source[lexer.pos] >= '0' and
      lexer.source[lexer.pos] <= '9':
    let digit = I64(ord(lexer.source[lexer.pos]) - ord('0'))
    if value > (high(I64) - digit) div I64(10):
      return LexInvalidInteger
    value = value * I64(10) + digit
    inc lexer.pos
  token.kind = TokenInteger
  token.value = value
  LexOk


## Parses one quoted string while retaining assembler-compatible escape text.
proc readString(lexer: var Lexer, token: var Token): LexStatus =
  inc lexer.pos
  var len = U32(0)
  var decodedLen = U32(0)
  while lexer.pos < lexer.size and lexer.source[lexer.pos] != '"':
    let ch = lexer.source[lexer.pos]
    if ch == '\n' or ch == '\r':
      return LexInvalidString
    if ch == '\\':
      if lexer.pos + U32(1) >= lexer.size:
        return LexInvalidString
      let escaped = lexer.source[lexer.pos + U32(1)]
      if escaped != 'n' and escaped != 'r' and escaped != 't' and
          escaped != '0' and escaped != '\\' and escaped != '"':
        return LexInvalidString
      if len + U32(2) >= U32(TokenTextCapacity):
        return LexTokenTooLong
      token.text[len] = '\\'
      token.text[len + U32(1)] = escaped
      len = len + U32(2)
      lexer.pos = lexer.pos + U32(2)
    else:
      if len + U32(1) >= U32(TokenTextCapacity):
        return LexTokenTooLong
      token.text[len] = ch
      inc len
      inc lexer.pos
    inc decodedLen
  if lexer.pos >= lexer.size or lexer.source[lexer.pos] != '"':
    return LexInvalidString
  inc lexer.pos
  token.text[len] = '\0'
  token.kind = TokenString
  token.stringLen = decodedLen
  LexOk


## Reads the next source token and reports malformed input without allocation.
proc nextToken*(lexer: var Lexer, token: var Token): LexStatus =
  token = Token()
  lexer.skipIgnored()
  if lexer.pos >= lexer.size:
    token.kind = TokenEof
    return LexOk

  let ch = lexer.source[lexer.pos]
  if isIdentifierStart(ch):
    return lexer.readIdentifier(token)
  if ch >= '0' and ch <= '9':
    return lexer.readInteger(token)
  if ch == '"':
    return lexer.readString(token)

  inc lexer.pos
  case ch
  of '(':
    token.kind = TokenLeftParen
  of ')':
    token.kind = TokenRightParen
  of '{':
    token.kind = TokenLeftBrace
  of '}':
    token.kind = TokenRightBrace
  of '[':
    token.kind = TokenLeftBracket
  of ']':
    token.kind = TokenRightBracket
  of ';':
    token.kind = TokenSemicolon
  of '+':
    token.kind = TokenPlus
  of '-':
    token.kind = TokenMinus
  of '*':
    token.kind = TokenStar
  of '/':
    token.kind = TokenSlash
  of '%':
    token.kind = TokenPercent
  of '&':
    token.kind = TokenAmpersand
  of '|':
    token.kind = TokenPipe
  of '^':
    token.kind = TokenCaret
  of '<':
    if lexer.pos < lexer.size and lexer.source[lexer.pos] == '=':
      inc lexer.pos
      token.kind = TokenLessEqual
    elif lexer.pos < lexer.size and lexer.source[lexer.pos] == '<':
      inc lexer.pos
      token.kind = TokenShiftLeft
    else:
      token.kind = TokenLess
  of '>':
    if lexer.pos < lexer.size and lexer.source[lexer.pos] == '=':
      inc lexer.pos
      token.kind = TokenGreaterEqual
    elif lexer.pos < lexer.size and lexer.source[lexer.pos] == '>':
      inc lexer.pos
      token.kind = TokenShiftRight
    else:
      token.kind = TokenGreater
  of ',':
    token.kind = TokenComma
  of '=':
    if lexer.pos < lexer.size and lexer.source[lexer.pos] == '=':
      inc lexer.pos
      token.kind = TokenEqual
    else:
      token.kind = TokenAssign
  of '!':
    if lexer.pos < lexer.size and lexer.source[lexer.pos] == '=':
      inc lexer.pos
      token.kind = TokenNotEqual
    else:
      return LexUnexpectedCharacter
  else:
    return LexUnexpectedCharacter
  LexOk
