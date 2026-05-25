# rkld

`rkld` is the hosted linker responsible for combining relocatable RKO object
files into runnable RKX applications. It concatenates each object section,
resolves `la`, branch, and `call`/jump relocations at final virtual addresses,
and emits the executable through the shared RKX writer.

## Usage

```text
rkld <input.rko> [input.rko...] -o <output.rkx>
```

The initial symbol model exposes each assembler label to the linker. Source
modules should therefore use distinct label names until local/global symbol
visibility is introduced.
