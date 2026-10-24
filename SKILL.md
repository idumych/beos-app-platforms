---
name: beos-app-platforms
description: Build, package, test and release BeOS-style apps (C++ against the Be/Haiku API) for Renku OS (the Haiku fork; .hpkg), VitruvianOS (Haiku API on Linux; .deb) and plain Linux through the Cosmoe library (AppImage). Covers one source tree for all three, porting traps, Makefile platform detection, and a complete release pipeline: onboarding templates (packaging scripts, GitHub CI for the .debs and AppImage), building, testing every package in headless VirtualBox VMs (keyboard, mouse, screenshots, SSH) or under Xvfb, and a release gate that stops for a human before publishing. Use this whenever the task involves building, porting or packaging a Haiku-API app for any of these systems, cutting or verifying a release, booting or driving a test VM, checking that an app runs on Renku/VitruvianOS/Linux, or reporting a platform bug upstream, even if the user just says "test it on Renku", "make a release", "does it still work on V\OS", "port it to Linux" or "check the AppImage".
---

# Building and testing BeOS-style apps on Renku OS, VitruvianOS and Linux (Cosmoe)

A BeOS-style app is C++ written against the Be/Haiku API (BApplication, BWindow, BView, the storage kit, node monitoring, attributes, Tracker). One source tree can ship on three platforms:

| Platform | What it is | Package | Built where | Tested how |
|---|---|---|---|---|
| **Renku OS** | Fork of Haiku; still names its system package `haiku`, version `r1~beta6` | `.hpkg` (`package create`) | Inside a Haiku R1/beta6 VM, over SSH (installs on Renku too) | VirtualBox VM: keyboard, mouse, screenshots |
| **VitruvianOS** (V\OS) | Haiku API on a Linux kernel, Debian userland | `.deb` installing to `/system/apps`, **amd64 and arm64** | In CI, natively per architecture, with a link-time SDK | VirtualBox VM (UEFI; amd64 only) |
| **Linux** | Any desktop, through the Cosmoe library (the Hokku fork) | AppImage | **CI** (Ubuntu 24.04) for releases; locally only for porting | Xvfb + Openbox (X11); headless sway in CI (Wayland) |

Read the reference file for what you're doing:

- **Releasing** (any of "release X", "build X for all platforms", "set up X for packaging"): `references/release.md` first. It runs the phases and points to the rest:
  - `references/onboard.md`: set an app up once: `haiku-app.env`, the Makefile contract, copying `templates/`, the app's `release/test-plan.md`
  - `references/release-test.md`: test each artifact on its platform and write the evidence the gate reads; the two shared test VMs
- `references/renku.md`: Renku OS (and Haiku-family guests in general): VM, SSH, building and checking an `.hpkg`, tests
- `references/vitruvianos.md`: VitruvianOS: the SDK, `.deb` packaging (attributes need special handling), VM, tests
- `references/cosmoe-linux.md`: Linux / Cosmoe: porting traps, the Makefile branch, AppImage bundling, CI, headless tests
- `references/virtualbox.md`: driving any VM: scancodes, mouse via the VirtualBox SDK, screenshots, files in and out
- `references/folio.md`: worked example: the Folio notebook app (github.com/idumych/folio), an app onboarded with the templates

Helper scripts in `scripts/` (read each script's header first):

- `make-vm.sh NAME IMAGE [efi]`: create and boot a VM from a copy of an ISO or raw image
- `vm.sh STEP…`: drive a VM (`VM=name`): `k:` scancodes, `t:` text, `m:` mouse, `w:` wait, `shot:` screenshot
- `mouse.py`: absolute mouse input through `vboxapi` (needs the `virtualbox-sdk` package)
- `xtest.sh STEP…`: drive a Cosmoe app under Xvfb (`APP=`, `APP_NAME=`; `start`, held clicks, keys, screenshots)
- `serve-ssh-setup.sh`: one-time key-only SSH setup for a Haiku-family guest
- `redactshot.py`: screenshot with private areas (account IDs, keys) blacked out before anything is written to disk
- `ocr-find.sh SHOT [WORD|--text]`: a screenshot as text, with click positions
- `check-artifact.sh deb|hpkg|appimage FILE`: static checks of a package
- `release-gate.sh`: the final yes/no for a release, from raw evidence only

`templates/` holds what onboarding copies into an app: `haiku-app.env`, a three-platform `Makefile`, `packaging/` (hpkg, deb + postinst, AppImage with Hokku, Wayland smoke test), `.github/workflows/` (`appimage.yml`, `deb.yml`, `test.yml`) and `tools/` (Haiku type-check, V\OS link-time SDK).

## Rules that matter

- **Never contact the Haiku project** (no Trac tickets, patches or forum posts), even for bugs that Renku or Cosmoe inherited from Haiku: the user says Haiku doesn't welcome AI contributions. Upstream reports go to **RenkuOS/Source** (AI-assisted work is explicitly allowed; keep write-ups short and plain); Cosmoe bugs are fixed in Hokku, never reported to haydentech/cosmoe (see below). File only after reproducing the bug in the platform's own code or bundled apps, not just in your app.
- **Build release packages in CI, not against the user's local libraries,** unless the user says otherwise (release.md § CI). The `.hpkg` is built in a Haiku R1/beta6 VM.
- **Target amd64 and arm64 for VitruvianOS** by default: one `deb.yml` job per architecture on `ubuntu-24.04` / `ubuntu-24.04-arm` in `debian:trixie` (`templates/.github/workflows/deb.yml`). arm64 gets static checks, since VirtualBox can't run arm64 guests on x86.
- **Linux builds use Hokku**, the user's Cosmoe fork (github.com/idumych/hokku): fix Cosmoe bugs there instead of working around them in apps, and never contribute upstream (cosmoe-linux.md).
- **Linux means X11 and Wayland:** Cosmoe picks its backend from `WAYLAND_DISPLAY` / `COSMOE_BACKEND`; the AppImage bundles both, and `appimage.yml` smoke-tests it on headless sway (cosmoe-linux.md).
- **Test the exact artifact you publish.** Build every package from one commit, test those files, publish them only after the release gate passes and a human says so, then re-test from the release URLs.
- **Don't build release AppImages on an Arch/CachyOS host.** CachyOS packages are built for x86-64-v3 (AVX2), and rolling-release glibc is newer than most distros'. An AppImage built there crashes on older CPUs and won't start on Ubuntu 24.04. Build releases in CI on the oldest supported distro.
- **Never capture or type the user's secrets.** Don't type passwords or account IDs into a VM: run the command and let the user answer the `sudo`/login prompt. If an app shows an account ID or similar, take every screenshot with `redactshot.py` and keep the private part out of the shot (see virtualbox.md).
- **Report results honestly.** "Type-checked" isn't "ran", and a headless X11 run isn't a Wayland run. Keep the README's platform table and the release notes' "Tested" section in step with what was actually exercised.
- **Keep platform code contained.** Put the logic you can test anywhere in a portable core with no Haiku headers. Put platform differences in the Makefile's platform branches and behind a define such as `-DAPP_COSMOE`, never scattered through the code.

## One source tree, three targets

A single Makefile can detect the platform. Check in this order and stop at the first match:

1. `uname -s` is `Haiku`: Haiku/Renku. Link `-lbe -ltracker -ltranslation`, resources via `rc` and `xres`.
2. `pkg-config --exists vos`, or `$(VOS_HEADERS)/os/BeBuild.h` exists: VitruvianOS (details in vitruvianos.md).
3. `$(COSMOE_ROOT)/include/os/app/Application.h` exists: Cosmoe (details in cosmoe-linux.md).
4. Otherwise print what's needed and fail. The portable unit tests should still build anywhere.

Keep `CXXFLAGS` additive (`override CXXFLAGS +=`) so packagers can pass hardening flags. `templates/Makefile` implements all of this (onboard.md §3).

## Releasing

`references/release.md` is the procedure: onboard once, host checks, push and CI, README screenshots, the final build of all three from one commit, a test of every artifact on its platform, notes and `SHA256SUMS`, then `scripts/release-gate.sh`. When it prints `GATE PASSED`, stop and wait for the human to say "publish".

## Platform cheat sheet

| | Renku OS / Haiku | VitruvianOS | Linux (Cosmoe) |
|---|---|---|---|
| Command key | **Alt** | **Ctrl** | **Ctrl** |
| Install | `pkgman install ./x.hpkg` | `sudo apt install ./x.deb` | AppImage: `chmod +x`, run |
| System apps | `/boot/system/apps` | `/system/apps` | inside the AppImage |
| Attributes | BFS, indexable; `listattr`, `query` | `user.beos.*` xattrs (**dpkg drops them**) | `user.*` xattrs, plus `user.COSMOE:ATTR_TYPES` |
| Queries | yes (`mkindex` / `fs_create_index`) | not yet | no |
| Trash | `/boot/trash` + `_trk/original_path` attr | `~/config/data/Trash/{files,info}` (XDG layout) | `~/.local/share/Trash/{files,info}` |
| `B_USER_SETTINGS_DIRECTORY` | `~/config/settings` | `~/config/settings` | `~/.config/cosmoe` |
| Node monitor | Haiku ints, leaf `name` | `virtual:*` node_ref / entry_refs | **full-path** `name`; upstream Cosmoe: only `watch_path()` works and fields are dev_t/ino_t-typed (both fixed in Hokku) |
| `entry_ref::name` | leaf | leaf | **full path** |
| Open folder/URL | `be_roster->Launch` | `be_roster->Launch` | `xdg-open` |
| Underline/strikeout faces | drawn | drawn | drawn in Hokku (upstream Cosmoe: not drawn) |

## A quick smoke test (outside a release)

Install the package, launch it from a terminal with stdout/stderr going to a log (it should stay empty), check it appears where users start apps and that its signature survived packaging, then exercise what differs per platform: file chooser, drag and drop, Trash, attributes and queries, renames from outside the app (node monitoring), opening links. Check results on disk rather than on screen, and at the VM's resolution (Haiku-family 1024×768). For a release, release-test.md does this in full.
