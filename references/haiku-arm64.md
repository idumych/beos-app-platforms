# Renku OS arm64 `.hpkg`

arm64 builds target **Renku OS**, not Haiku. There's no Haiku R1/beta6 arm64 release, and arm64
builds no longer use Haiku's master repository or nightlies. Renku has an arm64 system repository
(`haiku`, `haiku_devel`), an arm64 ports repository and an arm64 image for QEMU (renku.md
§ arm64). The app is cross-built on Linux against Renku's packages and tested on Renku arm64 in
QEMU. Libraries the app needs either come from Renku's arm64 ports repository (then the package
`requires` them) or are cross-built and linked in statically, so the package requires only
`haiku`. Powergram 0.2.5 (TDLib, OpenSSL, zlib) was done the second way, against Haiku's master
repository, before Renku had arm64 packages.

Renku's repositories are for Renku OS only: never add them to a Haiku system or use their
packages in a build meant for Haiku (renku.md § Renku's repositories).

## What arm64 lacks

Check `sysroot/lib` and `sysroot/add-ons` after `make-sysroot.sh`, and compare with x86_64.
Renku arm64 (hrev60072_940) **has** the Media Kit (`libmedia.so` and the media add-ons) and
`libgame`, unlike Haiku's arm64 builds (hrev60397), which had neither. Translators aren't in the
`haiku` package: they're in Renku's `haiku_datatranslators`, so an app that decodes pictures
requires that package. There's no WebPositive on arm64. Re-check the sysroot at each Renku build. Where something is missing, build stand-ins for those files on arm64
(Powergram: `src/app/NoMediaKit.cpp`, picked by `make HAIKU_CROSS=1`) and say in the release notes
what doesn't work.

RenkuOSPorts arm64 (`https://renkuos.freemyip.com/repo/renkuosports/arm64/`) has about 340 ports
(openssl3, zlib, opus, libogg, ffmpeg 6/8, libjpeg_turbo, libpng16, libwebp, SDL2…), so check
there before cross-building a library yourself.

## Build

    sh tools/haiku-arm64/make-sysroot.sh ~/.cache/haiku-arm64   # once, ~20 min, ~3 GB; cache it
    . ~/.cache/haiku-arm64/env.sh
    sh tools/haiku-arm64/build-deps.sh                          # only if the app needs HaikuPorts libraries
    sh packaging/build-hpkg-arm64.sh

- `make-sysroot.sh` builds the cross gcc and the host tools (`package`, `rc`, `xres`, `addattr`,
  `bfs_shell`) from `RenkuOS/Source` with Haiku's buildtools, and a sysroot from Renku's arm64
  `haiku` + `haiku_devel` plus `gcc_syslibs`, `icu74` and `zlib` from Renku's arm64 ports
  repository. Rerun it when Renku's arm64 repository moves to a new build (it checks the
  version and does nothing otherwise). `env.sh` exports `HAIKU_ARM64`,
  `CC`/`CXX`, `HAIKU_CROSS_CFLAGS` and `HAIKU_CROSS_LDFLAGS`.
- **Header order:** kit headers with `-I`; the C library's with `-idirafter`, in the order
  **bsd, gnu, posix**. `posix/features.h` is an empty stand-in, and `bsd/features.h` must win to
  define `_DEFAULT_SOURCE`, or `NI_MAXHOST`, `h_errno` and friends are missing. They go after
  the compiler's C++ headers, or libstdc++'s `#include_next <stdlib.h>` fails.
- configure insists on an ELF-capable `nasm` even for arm64; the script uses a stub.
- **flex 2.6.10 (CachyOS, Nov 2026) breaks the cross gcc**: gcc 13's generated `gengtype-lex.cc`
  fails with "variable or field 'yy_start' declared void". The compiler doesn't depend on which
  system's packages the sysroot comes from, so copy a `generated/cross-tools-arm64` built
  earlier into the work folder (the script then configures the tree around it), or build with
  flex 2.6.4.
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

Test on Renku's arm64 image (renku.md § arm64), not a Haiku nightly. Download it next to its
`.sha256`, check it, `zstd -d` it, then install it onto a properly sized disk, as for every test
VM:

    DIR=~/VMs/<app>-arm64 sh scripts/haiku-arm64-vm.sh create RenkuOS-arm64-<date>-build<NNN>.img
    DIR=… sh scripts/haiku-arm64-vm.sh start install

Keep `DIR` short: QEMU's monitor and QMP sockets live there, and a Unix socket path over 108
characters is cut off, so `start` never sees the VM come up and `shot` fails.

`create` makes a 20 GB `disk.img` with the image's EFI partition copied over and an empty BFS
partition (Renku's arm64 image has the same layout as Haiku's: EFI at sector 8192, BFS after it).
In the booted image:

1. DriveSetup: `virtio_block/0/1` (the 20 GB disk's "Unknown (Be File System)"), Partition >
   Format > Be File System, named e.g. "Test" (not the image's own volume name).
2. Installer: from the image's volume onto Test, Begin. Then "Boot sector has been written".
3. `shutdown`, then `start` (without `install`) boots the installed disk on its own.

**Open issue (build00090, 16 Nov 2026): only the first boot of a fresh image works.** Every
later boot of the same image, after QEMU was stopped, hangs on the RENKUOS splash (5 of 5; the
serial log ends at `register_domain(4, link)`, and `usb_hid` never loads, so Alt+SysRq+D can't
reach KDL). Reported as RenkuOS/Source#480; the same pattern as build00064 on x86_64 (renku.md
§ When it hangs). Until it's fixed, decompress a fresh copy for every boot: install the app's
package in that first boot (`put` can't help, since it needs a clean shutdown first), and expect
the Installer step above to fail, since the installed disk's first boot is the image's second.
Renku arm64 ignores QEMU's ACPI power-off, so shut down from the Deskbar.

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
- It's emulated (TCG): Haiku's nightly booted in about a minute (`start` waits for the
  input_server's screen_saver line), and each action takes a few seconds.
- Copy logs out with `bfs_shell` after `shutdown` (partition 2 starts at sector 73728).

Run the same feature checks as on x86_64, or say why one can't run (e.g. no browser). Write
`dist/V/evidence/haiku-arm64.txt`. The release notes say it ran on Renku's arm64 image in QEMU,
not on hardware, and list what arm64 lacks there (§ What arm64 lacks).
