## Supplies the freestanding Nim panic hook shared by toolchain applications.


## Ignores panic text because the optional runtime has no panic formatter.
proc rawoutput(msg: string) =
  discard msg


## Stops a faulting optional toolchain application without unwinding.
proc panic(msg: string) {.noreturn.} =
  rawoutput(msg)
  while true:
    asm "wfi"
