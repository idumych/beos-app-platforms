# Haiku arm64 `.hpkg`

There's no R1/beta6 arm64 release and no HaikuPorts arm64 repository (Oct 2026), but Haiku's
**master** arm64 repository has `haiku` and `haiku_devel`. That is enough for an app that links
only Haiku's own libraries (libbe, libtracker, libtranslation, libroot): it is cross-built on Linux
and tested on an arm64 nightly in QEMU. An app that needs anything from HaikuPorts (FFmpeg,
sqlite, openssl, Qt…) can't be built for arm64 yet; say "Haiku: x86_64 only" in the release notes.

## Build

    sh tools/haiku-arm64/make-sysroot.sh .haiku-arm64      # once, ~20 min, ~3 GB; cache it
    . .haiku-arm64/env.sh
    make HAIKU_CROSS=1 LDFLAGS=-s && sh packaging/build-hpkg-arm64.sh

- `make-sysroot.sh` builds Haiku's cross gcc at the hrev the arm64 repository is at, the host
  tools (`package`, `rc`, `xres`, `bfs_shell`) with jam, and a sysroot from `haiku` +
  `haiku_devel` plus the bootstrap `gcc_syslibs`, `icu` and `zlib` packages, which on arm64 exist
  only inside the nightly image (copied out with `bfs_shell`).
- Header order matters: kit headers with `-I`, the C library's (`posix`, `gnu`, `bsd`) with
  `-idirafter`, as Haiku's native compiler does; otherwise libstdc++'s `#include_next <stdlib.h>`
  fails. `env.sh` sets this up.
- configure insists on an ELF-capable `nasm` even for arm64; the script uses a stub.
- Don't run the host `mimeset` on arm64 binaries: it doesn't recognise them and writes
  `BEOS:TYPE` = `application/octet-stream`. `build-hpkg-arm64.sh` sets the type explicitly.
- The package says `requires haiku >= r1~beta6`; check the binary is aarch64 (ELF byte 18 = `b7`).

## Test (QEMU; VirtualBox can't run arm64 guests on x86)

    sh scripts/haiku-arm64-vm.sh create haiku-master-hrevNNNNN-arm64-mmc.image   # the nightly matching the sysroot
    sh scripts/haiku-arm64-vm.sh put <app>-arm64.hpkg /myfs/home/config/packages/ # VM stopped; installs on boot
    sh scripts/haiku-arm64-vm.sh start && sh scripts/haiku-arm64-vm.sh shot arm64-desktop

The nightly has no SSH server: drive it with `click X Y`, `key`, `type` and `shot` (QMP and the
QEMU monitor), read screenshots with `ocr-find.sh`. It's emulated (TCG), so allow a minute to
boot and a few seconds per action. Run the same feature checks as on x86_64 and write
`dist/V/evidence/haiku-arm64.txt`; the release notes say it ran on a nightly in QEMU, not on
R1/beta6 or hardware.
