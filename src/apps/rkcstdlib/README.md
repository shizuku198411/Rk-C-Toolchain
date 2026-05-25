# rkcstdlib

`rkcstdlib` installs the public C-like development header and linkable
userspace standard library for the hosted Rk-C toolchain.

The command is restricted to `uid=0` because it manages root-owned files in
`/usr/include` and `/usr/lib`:

```sh
sudo rkcstdlib --install
```

The initial installation creates `/usr/include/rkc.h` and
`/usr/lib/librkc.rko`, exporting `puts`, `strlen`, `write`, and `exit`.
