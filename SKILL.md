---
name: beos-app-platforms
description: Build, package, test and release BeOS-style apps (C++ against the Be/Haiku API) for Renku OS (the Haiku fork; .hpkg) and plain Linux through the Cosmoe library (AppImage). Covers one source tree for both, porting traps, Makefile platform detection, and a complete release pipeline: onboarding templates (packaging scripts, GitHub CI for the AppImage), building, testing every package in headless VirtualBox VMs (keyboard, mouse, screenshots, SSH) or under Xvfb, and a release gate that stops for a human before publishing. Also covers porting an app from Qt, GTK or another toolkit to the native Haiku API, starting from reference screenshots of the original. Use this whenever the task involves building, porting or packaging a Haiku-API app for any of these systems, cutting or verifying a release, booting or driving a test VM, checking that an app runs on Renku/Linux, theming Renku/Haiku (window decorators, control looks, system colours and fonts), or reporting a platform bug upstream, even if the user just says "test it on Renku", "make a release", "port it to Linux", "port this to the native Haiku UI" or "check the AppImage".
---

# Building and testing BeOS-style apps on Renku OS and Linux (Cosmoe)

A BeOS-style app is C++ written against the Be/Haiku API (BApplication, BWindow, BView, the storage kit, node monitoring, attributes, Tracker). One source tree can ship on two platforms:

| Platform | What it is | Package | Built where | Tested how |
|---|---|---|---|---|
| **Renku OS** | Fork of Haiku; still names its system package `haiku`, version `r1~beta6` | `.hpkg` (`package create`), x86_64; arm64 cross-built for apps needing only Haiku's own libraries | Inside a Haiku R1/beta6 VM, over SSH (installs on Renku too) | VirtualBox or QEMU VM: keyboard, mouse, screenshots, captured audio |
| **Linux** | Any desktop, through the Cosmoe library (the Hokku fork) | AppImage, **x86_64 and aarch64** | **CI** (Ubuntu 24.04, natively per architecture) for releases; locally only for porting | Xvfb + Openbox (X11); in CI on both architectures, X11 and headless sway (Wayland) |

Read the reference file for what you're doing:

- **Releasing** (any of "release X", "build X for all platforms", "set up X for packaging"): `references/release.md` first. It runs the phases and points to the rest:
  - `references/onboard.md`: set an app up once: `haiku-app.env`, the Makefile contract, copying `templates/`, the app's `release/test-plan.md`
  - `references/release-test.md`: test each artifact on its platform and write the evidence the gate reads; the two shared test VMs
- `references/haiku-arm64.md`: the arm64 `.hpkg`: cross toolchain and sysroot on Linux, the QEMU test machine, what can't be built yet
- **Porting an app to the native Haiku API** (from Qt, GTK, SDL…): `references/porting.md`: first a check that it hasn't been ported already, then reference screenshots of the original, structure, API traps, a vector icon, testing through `hey`, README screenshots
- `references/renku.md`: Renku OS (and Haiku-family guests in general): VM (VirtualBox or QEMU), the boot hang, SSH, building on Renku when `haiku_devel` lags, checking an `.hpkg`, tests
- `references/media-kit.md`: audio apps: a filter node between the system mixer and the sound card, the mixer auto-start trap, end-to-end audio tests from QEMU's capture of the guest's sound card
- `references/cosmoe-linux.md`: Linux / Cosmoe: porting traps, the Makefile branch, AppImage bundling, CI, headless tests
- `references/virtualbox.md`: driving any VM: scancodes, mouse via the VirtualBox SDK, screenshots, files in and out
- **Theming Renku/Haiku** (a window decorator, control look, colours, fonts): `references/theming.md`: app_server decorator add-ons, control looks on `HaikuControlLook`, a theme tool with revert, one look for many system builds, comparing against reference art; Gonx as the example
- `references/folio.md`: worked example: the Folio notebook app (github.com/idumych/folio), an app onboarded with the templates

Helper scripts in `scripts/` (read each script's header first):

- `make-vm.sh NAME IMAGE [efi]`: create and boot a VirtualBox VM from a copy of an ISO or raw image
- `qemu-vm.sh create|start|stop|shot|click|key|type`: the same in QEMU/KVM (x86_64), with the guest's audio output written to a WAV file
- `vm.sh STEP…`: drive a VM (`VM=name`): `k:` scancodes, `t:` text, `m:` mouse, `w:` wait, `shot:` screenshot
- `mouse.py`: absolute mouse input through `vboxapi` (needs the `virtualbox-sdk` package and a USB-tablet pointer in the VM)
- `hey-ui.sh`: shell functions to source in a Haiku guest that send mouse messages and commands to an app's views with `hey` (when clicks don't work)
- `make-hvif-icon.py`: encodes a vector app icon (HVIF) as an .rdef resource, with an SVG preview
- `xtest.sh STEP…`: drive a Cosmoe app under Xvfb (`APP=`, `APP_NAME=`; `start`, held clicks, keys, screenshots)
- `serve-ssh-setup.sh`: one-time key-only SSH setup for a Haiku-family guest
- `redactshot.py`: screenshot with private areas (account IDs, keys) blacked out before anything is written to disk
- `ocr-find.sh SHOT [WORD|--text]`: a screenshot as text, with click positions
- `tone.cpp` (built in the guest) and `sine-check.py`: play a sine through the system mixer and measure its level and dropouts in the captured WAV
- `haiku-arm64-vm.sh`: a Haiku arm64 nightly in QEMU (start, screenshots, pointer and keys over QMP, copy files in); `qmp-input.py` is its pointer helper
- `check-artifact.sh hpkg|appimage FILE`: static checks of a package
- `release-gate.sh`: the final yes/no for a release, from raw evidence only

`templates/` holds what onboarding copies into an app: `haiku-app.env`, a two-platform `Makefile`, `packaging/` (hpkg, AppImage with Hokku, Wayland smoke test), `.github/workflows/` (`appimage.yml`, `test.yml`) and `tools/` (Haiku type-check, Haiku arm64 sysroot).

## Rules that matter

- **Check for an existing port before starting a new one.** Search HaikuPorts, the guest's repositories, the Haiku forum, GitHub and the upstream repository's forks and issues (porting.md §0), report what you found, and let the user decide before evaluating or writing code.
- **Never contact the Haiku project** (no Trac tickets, patches or forum posts), even for bugs that Renku or Cosmoe inherited from Haiku: the user says Haiku doesn't welcome AI contributions. Upstream reports go to **RenkuOS/Source** (AI-assisted work is explicitly allowed; keep write-ups short and plain); Cosmoe bugs are fixed in Hokku, never reported to haydentech/cosmoe (see below). File only after reproducing the bug in the platform's own code or bundled apps, not just in your app.
- **Build release packages in CI, not against the user's local libraries,** unless the user says otherwise (release.md § CI). The `.hpkg` is built in a Haiku R1/beta6 VM.
- **Build for both amd64 (x86_64) and arm64 (aarch64) on both platforms.** Every release ships both wherever the platform has an arm64 target:
  - **Linux:** one `appimage.yml` job per architecture on `ubuntu-24.04` / `ubuntu-24.04-arm`; each starts its AppImage under X11 and Wayland, so aarch64 runs on real arm64 hardware.
  - **Haiku/Renku arm64:** Haiku's master arm64 repository has `haiku`/`haiku_devel`, but there is no R1/beta6 arm64 release, no HaikuPorts arm64 repository and no Renku arm64 ISO. So: an app that links **only Haiku's own libraries** (libbe, libtracker, libtranslation) is cross-built on Linux (`templates/tools/haiku-arm64/make-sysroot.sh`, `make HAIKU_CROSS=1`, `packaging/build-hpkg-arm64.sh`) and run on a nightly in QEMU before it ships (`references/haiku-arm64.md`). An app that needs HaikuPorts libraries (FFmpeg, sqlite, openssl…) has no arm64 `.hpkg` yet: the release notes say Haiku is x86_64 only. Check again at every release (renku.md § arm64).
- **Linux builds use Hokku**, the user's Cosmoe fork (github.com/idumych/hokku): fix Cosmoe bugs there instead of working around them in apps, and never contribute upstream (cosmoe-linux.md).
- **Linux means X11 and Wayland:** Cosmoe picks its backend from `WAYLAND_DISPLAY` / `COSMOE_BACKEND`; the AppImage bundles both, and `appimage.yml` smoke-tests it on headless sway (cosmoe-linux.md).
- **Test the exact artifact you publish.** Build every package from one commit, test those files, publish them only after the release gate passes and a human says so, then re-test from the release URLs.
- **Don't build release AppImages on an Arch/CachyOS host.** CachyOS packages are built for x86-64-v3 (AVX2), and rolling-release glibc is newer than most distros'. An AppImage built there crashes on older CPUs and won't start on Ubuntu 24.04. Build releases in CI on the oldest supported distro.
- **Never capture or type the user's secrets.** Don't type passwords or account IDs into a VM: run the command and let the user answer the `sudo`/login prompt. If an app shows an account ID or similar, take every screenshot with `redactshot.py` and keep the private part out of the shot (see virtualbox.md).
- **Report results honestly.** "Type-checked" isn't "ran", and a headless X11 run isn't a Wayland run. Keep the README's platform table and the release notes' "Tested" section in step with what was actually exercised.
- **When porting an app, pull screenshots of the original before writing UI code**, and match its dimensions: find them in the project and package READMEs, on SourceForge/HaikuDepot/forums, or ask the user; if there are none, run the original in the VM and take them. Measure them (button and icon sizes, spacing, widths, number formats) and compare the native build side by side after every UI change (porting.md §1). Keep them in the scratchpad unless their licence allows committing them.
- **Keep platform code contained.** Put the logic you can test anywhere in a portable core with no Haiku headers. Put platform differences in the Makefile's platform branches and behind a define such as `-DAPP_COSMOE`, never scattered through the code.

## One source tree, two targets

A single Makefile can detect the platform. Check in this order and stop at the first match:

1. `uname -s` is `Haiku`: Haiku/Renku. Link `-lbe -ltracker -ltranslation`, resources via `rc` and `xres`.
2. `$(COSMOE_ROOT)/include/os/app/Application.h` exists: Cosmoe (details in cosmoe-linux.md).
3. Otherwise print what's needed and fail. The portable unit tests should still build anywhere.

Keep `CXXFLAGS` additive (`override CXXFLAGS +=`) so packagers can pass hardening flags. `templates/Makefile` implements all of this (onboard.md §3).

## Releasing

`references/release.md` is the procedure: onboard once, host checks, push and CI, README screenshots, the final build of both from one commit, a test of every artifact on its platform, notes and `SHA256SUMS`, then `scripts/release-gate.sh`. When it prints `GATE PASSED`, stop and wait for the human to say "publish".

## Platform cheat sheet

| | Renku OS / Haiku | Linux (Cosmoe) |
|---|---|---|
| Command key | **Alt** | **Ctrl** |
| Install | `pkgman install ./x.hpkg` | AppImage: `chmod +x`, run |
| System apps | `/boot/system/apps` | inside the AppImage |
| Attributes | BFS, indexable; `listattr`, `query` | `user.*` xattrs, plus `user.COSMOE:ATTR_TYPES` |
| Queries | yes (`mkindex` / `fs_create_index`) | no |
| Trash | `/boot/trash` + `_trk/original_path` attr | `~/.local/share/Trash/{files,info}` |
| `B_USER_SETTINGS_DIRECTORY` | `~/config/settings` | `~/.config/cosmoe` |
| Node monitor | Haiku ints, leaf `name` | **full-path** `name`; upstream Cosmoe: only `watch_path()` works and fields are dev_t/ino_t-typed (both fixed in Hokku) |
| `entry_ref::name` | leaf | **full path** |
| Open folder/URL | `be_roster->Launch` | `xdg-open` |
| Underline/strikeout faces | drawn | drawn in Hokku (upstream Cosmoe: not drawn) |

## A quick smoke test (outside a release)

Install the package, launch it from a terminal with stdout/stderr going to a log (it should stay empty), check it appears where users start apps and that its signature survived packaging, then exercise what differs per platform: file chooser, drag and drop, Trash, attributes and queries, renames from outside the app (node monitoring), opening links. Check results on disk rather than on screen, and at the VM's resolution (Haiku-family 1024×768). For a release, release-test.md does this in full.
