# Object Format

RKO is the small relocatable object representation shared by `rkas`, `rkcc`,
and `rkld` as the toolchain grows beyond direct RKX generation. The Nim source
is placed in `../rko_format/rko.nim` because `object` is a Nim keyword.

## RKO1 Layout

```text
RkoHeader (magic, version, section sizes, table counts, optional entry symbol)
text bytes
rodata bytes
data bytes
RkoSymbol[symbolCount]
RkoRelocation[relocationCount]
```

BSS is represented by its size only. Relocations retain symbolic `la`, branch,
and jump/call references until `rkld` assigns final RKX virtual addresses.
