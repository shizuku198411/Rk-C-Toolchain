## Encodes the supported RV64I instruction subset for the mini assembler.
from lib/types import I64, U32


## Encodes an I-format instruction with a signed twelve-bit immediate.
proc encodeI*(opcode, funct3, rd, rs1: U32, immediate: I64, value: var U32): bool =
  if immediate < I64(-2048) or immediate > I64(2047):
    return false

  value = (U32(immediate) and U32(0xfff)) shl U32(20)
  value = value or ((rs1 and U32(0x1f)) shl U32(15))
  value = value or ((funct3 and U32(0x7)) shl U32(12))
  value = value or ((rd and U32(0x1f)) shl U32(7))
  value = value or (opcode and U32(0x7f))
  true


## Encodes an R-format integer register instruction.
proc encodeR*(funct7, funct3, rd, rs1, rs2: U32): U32 =
  ((funct7 and U32(0x7f)) shl U32(25)) or
    ((rs2 and U32(0x1f)) shl U32(20)) or
    ((rs1 and U32(0x1f)) shl U32(15)) or
    ((funct3 and U32(0x7)) shl U32(12)) or
    ((rd and U32(0x1f)) shl U32(7)) or
    U32(0x33)


## Encodes an S-format store instruction with a signed twelve-bit offset.
proc encodeS*(funct3, rs1, rs2: U32, immediate: I64, value: var U32): bool =
  if immediate < I64(-2048) or immediate > I64(2047):
    return false

  let imm = U32(immediate) and U32(0xfff)
  value = ((imm shr U32(5)) shl U32(25)) or
    ((rs2 and U32(0x1f)) shl U32(20)) or
    ((rs1 and U32(0x1f)) shl U32(15)) or
    ((funct3 and U32(0x7)) shl U32(12)) or
    ((imm and U32(0x1f)) shl U32(7)) or
    U32(0x23)
  true


## Encodes a B-format conditional branch relative to its instruction address.
proc encodeB*(funct3, rs1, rs2: U32, displacement: I64, value: var U32): bool =
  if (displacement and I64(1)) != I64(0) or
      displacement < I64(-4096) or displacement > I64(4094):
    return false

  let imm = U32(displacement) and U32(0x1fff)
  value = (((imm shr U32(12)) and U32(1)) shl U32(31)) or
    (((imm shr U32(5)) and U32(0x3f)) shl U32(25)) or
    ((rs2 and U32(0x1f)) shl U32(20)) or
    ((rs1 and U32(0x1f)) shl U32(15)) or
    ((funct3 and U32(0x7)) shl U32(12)) or
    (((imm shr U32(1)) and U32(0xf)) shl U32(8)) or
    (((imm shr U32(11)) and U32(1)) shl U32(7)) or
    U32(0x63)
  true


## Encodes a U-format instruction such as LUI or AUIPC.
proc encodeU*(opcode, rd: U32, immediate: I64): U32 =
  (U32(immediate) and U32(0xfffff000'u32)) or
    ((rd and U32(0x1f)) shl U32(7)) or
    (opcode and U32(0x7f))


## Encodes a JAL instruction relative to its instruction address.
proc encodeJ*(rd: U32, displacement: I64, value: var U32): bool =
  if (displacement and I64(1)) != I64(0) or
      displacement < I64(-1048576) or displacement > I64(1048574):
    return false

  let imm = U32(displacement) and U32(0x1fffff)
  value = (((imm shr U32(20)) and U32(1)) shl U32(31)) or
    (((imm shr U32(1)) and U32(0x3ff)) shl U32(21)) or
    (((imm shr U32(11)) and U32(1)) shl U32(20)) or
    (((imm shr U32(12)) and U32(0xff)) shl U32(12)) or
    ((rd and U32(0x1f)) shl U32(7)) or
    U32(0x6f)
  true


## Encodes the AUIPC/ADDI pair used by the `la` pseudo instruction.
proc encodeLa*(rd: U32, displacement: I64, first, second: var U32): bool =
  if displacement < I64(-2147483648) or displacement > I64(2147483647):
    return false

  let high = (displacement + I64(0x800)) shr 12
  let low = displacement - (high shl 12)
  first = encodeU(U32(0x17), rd, high shl 12)
  encodeI(U32(0x13), U32(0), rd, rd, low, second)


## Encodes the `li` pseudo instruction and reports whether it occupies one or two words.
proc encodeLi*(rd: U32, immediate: I64, first, second: var U32, words: var U32): bool =
  if immediate >= I64(-2048) and immediate <= I64(2047):
    words = U32(1)
    return encodeI(U32(0x13), U32(0), rd, U32(0), immediate, first)

  if immediate < I64(-2147483648) or immediate > I64(2147483647):
    return false

  let high = (immediate + I64(0x800)) shr 12
  let low = immediate - (high shl 12)
  first = encodeU(U32(0x37), rd, high shl 12)
  words = U32(2)
  encodeI(U32(0x13), U32(0), rd, rd, low, second)
