## Builds bounded assembly text emitted by the hosted C-like compiler.
from lib/types import I64, U32


const
  AsmOutputCapacity* = 8192


type
  AsmOutput* = object
    data*: array[AsmOutputCapacity, char]
    len*: U32


## Initializes an empty assembly output buffer.
proc initAsmOutput*(output: var AsmOutput) =
  output = AsmOutput()


## Appends one character while preserving a trailing C string terminator.
proc appendChar*(output: var AsmOutput, ch: char): bool =
  if output.len + U32(1) >= U32(AsmOutputCapacity):
    return false

  output.data[output.len] = ch
  inc output.len
  output.data[output.len] = '\0'
  true


## Appends a C string to the bounded assembly output buffer.
proc appendText*(output: var AsmOutput, text: cstring): bool =
  var pos = U32(0)
  while text[pos] != '\0':
    if not output.appendChar(text[pos]):
      return false
    inc pos
  true


## Appends a decimal signed integer to the assembly output.
proc appendNumber*(output: var AsmOutput, value: I64): bool =
  var digits: array[24, char]
  var count = 0
  var magnitude: uint64

  if value < I64(0):
    if not output.appendChar('-'):
      return false
    magnitude = uint64(-(value + I64(1))) + uint64(1)
  else:
    magnitude = uint64(value)

  if magnitude == uint64(0):
    return output.appendChar('0')

  while magnitude > uint64(0):
    digits[count] = char(ord('0') + int(magnitude mod uint64(10)))
    magnitude = magnitude div uint64(10)
    inc count

  while count > 0:
    dec count
    if not output.appendChar(digits[count]):
      return false
  true


## Appends a line terminator to complete one generated assembly statement.
proc appendNewline*(output: var AsmOutput): bool =
  output.appendChar('\n')
