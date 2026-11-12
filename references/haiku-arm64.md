# Haiku arm64 `.hpkg`

There's no R1/beta6 arm64 release and no HaikuPorts arm64 repository (Nov 2026), but Haiku's
**master** arm64 repository has `haiku` and `haiku_devel`. That's enough to cross-build an app on
Linux and test it on an arm64 nightly in QEMU. Libraries the app needs from HaikuPorts (OpenSSL,
sqlite, TDLib…) are cross-built too and linked in statically, so the package requires only
`haiku`. Done for Powergram 0.2.5 (TDLib, OpenSSL, zlib).

## What Haiku arm64 lacks (hrev60397)

Check `sysroot/lib` and `sysroot/add-ons` after `make-sysroot.sh`. Missing on arm64:

- **The Media Kit:** no `libmedia.so`, no media add-ons or media_server. That rules out
  BSoundPlayer, BMediaFile, BMediaRecorder, and also `system_beep()` / `add_system_beep_event()`
  (declared in `Beep.h` but in libmedia). Build stand-ins for those files on arm64 (Powergram:
  `src/app/NoMediaKit.cpp`, picked by `make HAIKU_CROSS=1`) and say what doesn't work.
- **Translators:** no `add-ons/Translators`, so `BTranslationUtils` decodes no PNG, JPEG or WebP;
  pictures get the app's placeholders.
- **Apps:** no WebPositive, MediaPlayer or other HaikuPorts apps. Opening a URL starts Haiku's
  URL helper, which runs `wget` in a Terminal and fails. `libgame` and `libscreensaver` are
  missing too.
- What is there: libbe, libtracker, libtranslation, libnetwork, libbnetapi, libpackage, libstdc++,
  ICU, zlib (bootstrap), Terminal, StyledEdit, ShowImage, DriveSetup, Installer, Deskbar, Tracker.

Renku's arm64 depot (RenkuOSPorts, `https://renkuos.freemyip.com/repo/renkuosports/arm64/`) has
about 340 ports (openssl3, zlib, opus, libogg, ffmpeg 6/8, libjpeg_turbo, libpng16, libwebp,
SDL2…) but no `haiku` system package, so no Media Kit or translators either. There's no Renku
arm64 image (renku.md § arm64).

## Build

    sh tools/haiku-arm64/make-sysroot.sh ~/.cache/haiku-arm64   # once, ~20 min, ~3 GB; cache it
    . ~/.cache/haiku-arm64/env.sh
    sh tools/haiku-arm64/build-deps.sh                          # only if the app needs HaikuPorts libraries
    sh packaging/build-hpkg-arm64.sh

- `make-sysroot.sh` builds Haiku's cross gcc at the hrev the arm64 repository is at, the host
  tools (`package`, `rc`, `xres`, `addattr`, `bfs_shell`) with jam, and a sysroot from `haiku` +
  `haiku_devel` plus the bootstrap `gcc_syslibs`, `icu` and `zlib` packages, which on arm64 exist
  only inside the nightly image (copied out with `bfs_shell`). `env.sh` exports `HAIKU_ARM64`,
  `CC`/`CXX`, `HAIKU_CROSS_CFLAGS` and `HAIKU_CROSS_LDFLAGS`.
- **Header order:** kit headers with `-I`; the C library's with `-idirafter`, in the order
  **bsd, gnu, posix**. `posix/features.h` is an empty stand-in, and `bsd/features.h` must win to
  define `_DEFAULT_SOURCE`, or `NI_MAXHOST`, `h_errno` and friends are missing. They go after
  the compiler's C++ headers, or libstdc++'s `#include_next <stdlib.h>` fails.
- configure insists on an ELF-capable `nasm` even for arm64; the script uses a stub.
- **`build-deps.sh`** cross-builds zlib and OpenSSL 3.5.9 (HaikuPorts' version and patchset)
  into `$HAIKU_ARM64/deps`, with `cmake_lib` / `autotools_lib` helpers and a CMake toolchain
  file for the app's own libraries. Use HaikuPorts' versions, checksums and patchsets (fetched
  from haikuports/haikuports). The Makefile's cross mode adds `-I`/`-L $(HAIKU_ARM64)/deps`.
  Then set `HPKG_REQUIRES_ARM64=""` in `haiku-app.env`.
- **OpenSSL on arm64:**
  - Haiku's OpenSSL targets cover x86 only. `build-deps.sh` adds a `haiku-aarch64` target
    (BASE_unix, `asm_arch aarch64`, `perlasm_scheme linux64`). It can't inherit `haiku-common`:
    that adds `-include os-dep/haiku.h` to every compile, and the aarch64 `.S` files are
    preprocessed too, so the assembler gets C. Use a header guarded by `__ASSEMBLER__`, and
    write `cflags` with `add_before(…, threads(…))`: `threads()` returns code, not a string.
  - **Kernel panic:** at load time `OPENSSL_cpuid_setup` probes CPU features by catching
    SIGILL. Haiku arm64's kernel panics on the SVE probe ("PANIC: unhandled exception: 25",
    stack `_armv8_sve_probe` / `OPENSSL_cpuid_setup` / `runtime_loader`) instead of signalling
    the process. `openssl-haiku-arm64.patch` skips probing on `__HAIKU__` and uses NEON.
    `OPENSSL_armcap` in the environment can't help: setup runs as a constructor, before `main`.
- **TDLib** (Powergram's `tools/haiku-arm64/build-deps.sh`):
  - Generate its sources first with a native build (`-DTD_GENERATE_SOURCE_FILES=ON`, target
    `prepare_cross_compiling`; it needs `gperf`, built on the host if missing).
  - Then cross-build twice, as the recipe does: `TD_E2E_ONLY=OFF`, then `ON`.
  - The toolchain file needs `CMAKE_SHARED_LINKER_FLAGS_INIT` as well as the EXE one, or
    `libtdjson.so` can't find `crti.o`.
- Don't run the host `mimeset` on arm64 binaries: it doesn't recognise them and writes
  `BEOS:TYPE` = `application/octet-stream`. `build-hpkg-arm64.sh` writes `BEOS:TYPE` and
  `BEOS:APP_SIG` with the host `addattr` (`package list -a` shows them). It runs `make clean`
  at the end: arm64 objects left in `obj/` break a later `make test`.
- Check the binaries are aarch64 (ELF byte 18 = `b7`) and `readelf -d` lists only Haiku
  libraries (libbe, libtracker, libtranslation, libnetwork, libstdc++.so.6, libroot).
- With `/tmp` full, gcc fails with "error writing to /tmp/cc….s": export `TMPDIR`.

## Test (QEMU; VirtualBox can't run arm64 guests on x86)

Install onto a properly sized disk first, as for every test VM:

    DIR=~/VMs/<app>-arm64 sh scripts/haiku-arm64-vm.sh create haiku-master-hrevNNNNN-arm64-mmc.image
    DIR=… sh scripts/haiku-arm64-vm.sh start install

`create` makes a 20 GB `disk.img` with the nightly's EFI partition copied over and an empty BFS
partition. Use the nightly matching the sysroot; `make-sysroot.sh` leaves it in `packages/`. In
the booted nightly:

1. DriveSetup: `virtio_block/0/1` (the 20 GB disk's "Unknown (Be File System)"), Partition >
   Format > Be File System, named e.g. "Test" (not "Haiku", which is the nightly's name).
2. Installer: from Haiku onto Test, Begin. It takes seconds, then "Boot sector has been written".
3. `shutdown`, then `start` (without `install`) boots the installed disk on its own.

Then for each package:

    sh scripts/haiku-arm64-vm.sh put <app>-<V>-1-arm64.hpkg /myfs/home/config/packages/<app>-<V>-1-arm64.hpkg
    sh scripts/haiku-arm64-vm.sh start
    …drive it…
    sh scripts/haiku-arm64-vm.sh shutdown

- **Shut down only with `shutdown`** (Deskbar > Shutdown > Power off; arm64 can't power itself
  off, so the script quits QEMU at "safe to turn off"). After `stop`, a panic or a hang, BFS's
  journal is dirty, and the next boot replays it over anything `put` wrote, so the old package
  silently comes back. `put` refuses until a clean `start` + `shutdown`. If it already
  happened, `checkfs -c /boot` in the guest shows whether the disk is consistent.
- There's no SSH server. Drive the guest with `click X Y`, `key`, `type` and `shot`, and read
  screens with `ocr-find.sh`. Start the app from Terminal (Deskbar > Applications > Terminal,
  type the command name), so its output stays on screen. `type` handles letters, digits, space
  and `. / - _`; for others use `key`, e.g. `key shift-equal` for `+`.
- It's emulated (TCG): booting takes about a minute (`start` waits for the input_server's
  screen_saver line), and each action takes a few seconds.
- Copy logs out with `bfs_shell` after `shutdown` (partition 2 starts at sector 73728).

Run the same feature checks as on x86_64, or say why one can't run (e.g. no browser). Write
`dist/V/evidence/haiku-arm64.txt`. The release notes say it ran on a nightly in QEMU, not on
R1/beta6 or hardware, and list what arm64 lacks (no Media Kit or translators).
