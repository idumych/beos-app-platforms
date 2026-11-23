---
name: beos-app-platforms
description: Build, package, test and release BeOS-style apps (C++ against the Be/Haiku API) for Haiku R1/beta6 and Renku OS (.hpkg), VitruvianOS (V\OS, a BeOS-like OS based on Linux; .deb) and plain Linux through the Cosmoe library (AppImage). Covers one source tree for all of them, porting traps, Makefile platform detection, and a complete release pipeline: onboarding templates (packaging scripts, GitHub CI for the AppImage and the .debs), building, testing every package in headless QEMU VMs (keyboard, mouse, screenshots, SSH) or under Xvfb, and a release gate that stops for a human before publishing. Also covers porting an app from Qt, GTK or another toolkit to the native Haiku API, starting from reference screenshots of the original, and checking that every app follows the Haiku Human Interface Guidelines (menus, shortcuts, wording, alerts, windows, icons). Use this whenever the task involves building, porting or packaging a Haiku-API app for any of these systems, cutting or verifying a release, booting or driving a test VM, checking that an app runs on Renku, V\OS or Linux, theming Renku/Haiku (window decorators, control looks, system colours and fonts), running an original BeOS app on BeOS 5 in a VM to compare a port against it (screenshots, measurements), or reporting a platform bug upstream, even if the user just says "test it on Renku", "make a release", "port it to Linux", "port this to the native Haiku UI", "check it against the original" or "check the AppImage" or "test it on V\OS".
---

# Building and testing BeOS-style apps on Renku OS, VitruvianOS and Linux (Cosmoe)

A BeOS-style app is C++ written against the Be/Haiku API (BApplication, BWindow, BView, the storage kit, node monitoring, attributes, Tracker). One source tree can ship on three platforms:

| Platform | What it is | Package | Built where | Tested how |
|---|---|---|---|---|
| **Renku OS** | Fork of Haiku; still names its system package `haiku`, version `r1~beta6` | `.hpkg` (`package create`), x86_64; arm64 cross-built on Linux against Renku's arm64 packages | Inside a Haiku R1/beta6 VM, over SSH (installs on Renku too) | QEMU VM (`qemu-vm.sh`): keyboard, mouse, screenshots, captured audio |
| **VitruvianOS** (V\OS) | A BeOS-like OS based on Linux (the Haiku API on a Debian userland) | `.deb` installing to `/system/apps`, **amd64 and arm64** | In CI, natively per architecture, with a link-time SDK | QEMU: amd64 under KVM, arm64 emulated; installed onto a 20 GB disk |
| **Linux** | Any desktop, through the Cosmoe library (the Hokku fork) | AppImage, **x86_64 and aarch64** | **CI** (Ubuntu 24.04, natively per architecture) for releases; locally only for porting | Xvfb + Openbox (X11); in CI on both architectures, X11 and headless sway (Wayland) |

Read the reference file for what you're doing:

- **Releasing** (any of "release X", "build X for all platforms", "set up X for packaging"): `references/release.md` first. It runs the phases and points to the rest:
  - `references/onboard.md`: set an app up once: `haiku-app.env`, the Makefile contract, copying `templates/`, the app's `release/test-plan.md`
  - `references/release-test.md`: test each artifact on its platform and write the evidence the gate reads; the two shared test VMs
- `references/haiku-arm64.md`: the arm64 `.hpkg`: cross toolchain, sysroot from Renku's arm64 packages and static libraries on Linux, what arm64 lacks, the Renku arm64 test machine in QEMU
- **Porting an app to the native Haiku API** (from Qt, GTK, SDL… or from a decompiled BeOS binary): `references/porting.md`: first a check that it hasn't been ported already, then reference screenshots of the original, structure, API traps, porting from a decompiled original (§4b: Ghidra's quirks, strings from the binary, missing system data files, round-trip tests, a README progress table), a vector icon, testing through `hey` and the app's own `--do` script hooks, README screenshots
- **Porting a BeOS app: compare it with the original running on BeOS 5**, not Haiku: `references/beos.md`: getting BeOS 5.0.3 and installing it in VirtualBox, the warm-reset panic, the 1024×768 VESA mode, files in on a CD image, driving it without SSH (a steered PS/2 mouse, menus by keyboard, a Terminal), launching the original, and measuring the port against it; § 7: ZETA 1.21 as a reference for its looks (live CD, 1024×768×16 boot mode, German keymap, applying Theme Manager themes in it)
- **Every app follows the Haiku HIG** (designing, porting, onboarding, reviewing or releasing UI): `references/hig.md`: the checkable rules (menus and their order, reserved shortcuts, sentence case and `…`, alerts, windows, settings, controls, icons) and a review checklist
- `references/renku.md`: Renku OS (and Haiku-family guests in general): VM (QEMU), the boot hang, SSH, Renku's package repositories (Renku only), building on Renku, checking an `.hpkg`, tests
- `references/vitruvianos.md`: VitruvianOS (V\OS): the link-time SDK and CI for amd64 and arm64, `.deb` packaging (attributes need special handling), Deskbar tray items, QEMU test VMs, traps
- `references/media-kit.md`: audio apps: a filter node between the system mixer and the sound card, the mixer auto-start trap, end-to-end audio tests from QEMU's capture of the guest's sound card
- `references/cosmoe-linux.md`: Linux / Cosmoe: porting traps, the Makefile branch, AppImage bundling, CI, headless tests
- `references/virtualbox.md` (legacy: VirtualBox is no longer used; read it only for scancodes, screenshot cropping and the VM lock, which carry over to QEMU): driving any VM: scancodes, mouse via the VirtualBox SDK, screenshots, files in and out
- **Theming Renku/Haiku** (a window decorator, control look, colours, fonts): `references/theming.md`: app_server decorator add-ons, control looks on `HaikuControlLook`, a theme tool with revert, one look for many system builds (ship add-ons as source and build them on the user's system, fetching that build's exact headers), `TabDecorator` subclassing, recreating an old look from screenshots; Gonx and Power Theme as the examples
- `references/folio.md`: worked example: the Folio notebook app (github.com/idumych/folio), an app onboarded with the templates

Helper scripts in `scripts/` (read each script's header first):

- `make-vm.sh`, `vm.sh`, `mouse.py`, `beos-mouse.py` (legacy, VirtualBox only: don't use): `make-vm.sh NAME IMAGE [efi]` creates and boots a VirtualBox VM from a copy of an ISO or raw image
- `qemu-vm.sh create|start|stop|shot|click|key|type`: the same in QEMU/KVM (x86_64), with the guest's audio output written to a WAV file
- `vm.sh STEP…`: drive a VM (`VM=name`): `k:` scancodes, `t:` text, `m:` mouse, `w:` wait, `shot:` screenshot
- `mouse.py`: absolute mouse input through `vboxapi` (needs the `virtualbox-sdk` package and a USB-tablet pointer in the VM)
- `beos-mouse.py`: mouse input for a BeOS 5 guest (PS/2 only): finds the hand pointer in screenshots and steers it there; `beos-terminal.sh` opens a Terminal in it
- `hey-ui.sh`: shell functions to source in a Haiku guest that send mouse messages and commands to an app's views with `hey` (when clicks don't work)
- `make-hvif-icon.py`: encodes a vector app icon (HVIF) as an .rdef resource, with an SVG preview
- `wayland-input/build.sh`: builds `vptr` (virtual pointer for headless sway) and `ftouch` (touch through a nested KWin) for driving apps on headless Wayland (cosmoe-linux.md)
- `xtest.sh STEP…`: drive a Cosmoe app under Xvfb (`APP=`, `APP_NAME=`; `start`, held clicks, keys, screenshots)
- `serve-ssh-setup.sh`: one-time key-only SSH setup for a Haiku-family guest
- `redactshot.py`: screenshot with private areas (account IDs, keys) blacked out before anything is written to disk
- `ocr-find.sh SHOT [WORD|--text]`: a screenshot as text, with click positions
- `tone.cpp` (built in the guest) and `sine-check.py`: play a sine through the system mixer and measure its level and dropouts in the captured WAV
- `haiku-arm64-vm.sh`: a Renku OS arm64 test machine in QEMU (a 20 GB disk to install onto, start, clean shutdown, screenshots, pointer and keys over QMP, copy files in); `qmp-input.py` is its pointer helper
- `check-artifact.sh hpkg|deb|appimage FILE`: static checks of a package
- `release-gate.sh`: the final yes/no for a release, from raw evidence only

`templates/` holds what onboarding copies into an app: `haiku-app.env`, a `Makefile` for every platform, `packaging/` (hpkg, deb + postinst, AppImage with Hokku, Wayland smoke test), `.github/workflows/` (`appimage.yml`, `deb.yml`, `test.yml`) and `tools/` (Haiku type-check, Haiku arm64 sysroot and static libraries, V\OS link-time SDK).

## Rules that matter

- **No VirtualBox.** Every test VM runs in QEMU/KVM through `scripts/qemu-vm.sh` (x86_64) or `scripts/haiku-arm64-vm.sh` (arm64). Don't create, start, stop or snapshot VirtualBox VMs, even where an older reference file says to. To reuse an old VirtualBox VM, `qemu-img convert -O raw` its `.vdi` into a fresh `DIR` and boot that copy. Keep `DIR` short (e.g. `~/VMs/<name>`): the QEMU monitor socket path must stay under 108 characters, so a scratchpad path is too long. KVM and VirtualBox can't share the CPU, which is one more reason not to mix them.
- **Check for an existing port before starting a new one.** Search HaikuPorts, the guest's repositories, the Haiku forum, GitHub and the upstream repository's forks and issues (porting.md §0), report what you found, and let the user decide before evaluating or writing code.
- **Never contact the Haiku project or HaikuPorts** (no Trac tickets, GitHub issues, pull requests, recipe patches or forum posts), even for bugs that Renku or Cosmoe inherited from Haiku or that live in a HaikuPorts package: the user says Haiku doesn't welcome AI contributions. Don't draft such reports for the user to file either; note the bug in your report and work around it or fix it in Renku. Upstream reports go to **RenkuOS/Source** (AI-assisted work is explicitly allowed; keep write-ups short and plain); Cosmoe bugs are fixed in Hokku, never reported to haydentech/cosmoe (see below). File only after reproducing the bug in the platform's own code or bundled apps, not just in your app.
- **Renku's package repositories are for Renku OS only.** The system repositories (`https://renkuos.freemyip.com/repo/x86_64`, `/repo/arm64`, `/repo/x86_gcc2`) and the ports repositories (`/repo/renkuosports/<arch>`) go on Renku systems and into Renku-targeted builds (the arm64 sysroot), never onto a Haiku VM or into a build meant for Haiku (renku.md § Renku's repositories).
- **Build release packages in CI, not against the user's local libraries,** unless the user says otherwise (release.md § CI). The `.hpkg` is built in a Haiku R1/beta6 VM.
- **Every release ships six packages**, each tested where it runs:
  - the **Haiku R1/beta6 `.hpkg`, x86_64** (also installs on Renku OS x86_64);
  - the **Renku OS nightly `.hpkg`, arm64**;
  - the **Hokku AppImage, x86_64 and aarch64**;
  - the **V\OS `.deb`, amd64 and arm64**.

  Drop a platform only for an app that can't run there (`PLATFORMS` in `haiku-app.env`), and say why in the README and the release notes. How each is built:
  - **VitruvianOS:** one `deb.yml` job per architecture on `ubuntu-24.04` / `ubuntu-24.04-arm` in `debian:trixie`, against a link-time V\OS SDK. Both `.deb`s are installed and tested on V\OS in QEMU: amd64 under KVM, arm64 emulated (vitruvianos.md).
  - **Linux:** one `appimage.yml` job per architecture on `ubuntu-24.04` / `ubuntu-24.04-arm`; each starts its AppImage under X11 and Wayland, so aarch64 runs on real arm64 hardware.
  - **arm64 targets Renku OS, not Haiku:** there is no Haiku R1/beta6 arm64 release, and arm64 builds no longer use Haiku's master repository or nightlies. The app is cross-built on Linux against Renku's arm64 system packages (`templates/tools/haiku-arm64/make-sysroot.sh`, `make HAIKU_CROSS=1`, `packaging/build-hpkg-arm64.sh`), with libraries from Renku's arm64 ports repository or cross-built and linked in statically (`build-deps.sh`), and run on Renku's arm64 nightly image in QEMU, installed onto a 20 GB disk, before it ships (`references/haiku-arm64.md`). The release notes say it was tested on Renku arm64 and what doesn't work there (renku.md § arm64).
- **Linux builds use Hokku**, the user's Cosmoe fork (github.com/idumych/hokku): fix Cosmoe bugs there instead of working around them in apps, and never contribute upstream (cosmoe-linux.md).
- **Linux means X11 and Wayland:** Cosmoe picks its backend from `WAYLAND_DISPLAY` / `COSMOE_BACKEND`; the AppImage bundles both, and `appimage.yml` smoke-tests it on headless sway (cosmoe-linux.md).
- **Test the exact artifact you publish.** Build every package from one commit, test those files, publish them only after the release gate passes and a human says so, then re-test from the release URLs.
- **Don't build release AppImages on an Arch/CachyOS host.** CachyOS packages are built for x86-64-v3 (AVX2), and rolling-release glibc is newer than most distros'. An AppImage built there crashes on older CPUs and won't start on Ubuntu 24.04. Build releases in CI on the oldest supported distro.
- **Never capture or type the user's secrets.** Don't type passwords or account IDs into a VM: run the command and let the user answer the `sudo`/login prompt. If an app shows an account ID or similar, take every screenshot with `redactshot.py` and keep the private part out of the shot (see virtualbox.md).
- **Describe VitruvianOS as "a BeOS-like OS based on Linux"** wherever an app's README, release notes, package descriptions or docs introduce it (the user's wording). Technical detail (the Haiku API, Debian trixie) can follow.
- **Report results honestly.** "Type-checked" isn't "ran", and a headless X11 run isn't a Wayland run. Keep the README's platform table and the release notes' "Tested" section in step with what was actually exercised.
- **A BeOS app's port is checked against the original running on BeOS 5** (`references/beos.md`), not against Haiku's rendering or the decompiled coordinates alone: Haiku draws differently, and sizes, placement and colours were wrong in a port whose decompiled layout matched to the pixel.
- **When porting an app, pull screenshots of the original before writing UI code**, and match its dimensions: find them in the project and package READMEs, on SourceForge/HaikuDepot/forums, or ask the user; if there are none, run the original in the VM and take them. Measure them (button and icon sizes, spacing, widths, number formats) and compare the native build side by side after every UI change (porting.md §1). Keep them in the scratchpad unless their licence allows committing them.
- **Follow the Haiku Human Interface Guidelines** (https://www.haiku-os.org/community/getting-involved/designing/) in every app, on Linux too: standard menus and shortcuts through `B_COMMAND_KEY`, sentence case, `…` only before a window that asks for input, action-labelled alerts, remembered window sizes, settings in `B_USER_SETTINGS_DIRECTORY`, an HVIF icon to the Icon Guidelines. A port keeps the original's layout and sizes but takes Haiku's conventions. Check `references/hig.md` during UI work and before a release, and report deviations instead of skipping them.
- **Window decorators support Power Theme's BeOS-style tabs.** Every decorator with a title bar across the window also draws a narrow BeOS-style tab when `powertheme --beos-tabs=on` is set, and is registered in Power Theme's `draws_beos_tabs()`. A port isn't finished until that's been tested, in each of the theme's modes (theming.md § BeOS-style tabs).
- **Keep platform code contained.** Put the logic you can test anywhere in a portable core with no Haiku headers. Put platform differences in the Makefile's platform branches and behind a define such as `-DAPP_COSMOE`, never scattered through the code.

## Large ports: several agents at once

A big port (an office suite) goes faster split across a few agents, each
owning one README Status row:

- **A git worktree and branch per agent** (`git worktree add ../app-<name>
  -b <name>`), with symlinks for what isn't in git (the original's files,
  the decompiled tree, the VM folder). Agents never touch the main tree or
  each other's; you merge each branch when it reports, run the host suite
  and the Haiku type check on the merge, and push.
- **Give each agent a whole row and files of its own**; shared files
  (the main view, the README, the progress bar) will conflict, so keep their
  changes there to small hooks and resolve README conflicts by keeping each
  row's honest state, then regenerate the bar.
- **The shared test VM needs a lock** (virtualbox.md § Several agents).
- **Hand a finished agent its next row at once** (resume it with the new
  task rather than starting a fresh one), and respect the user's cap on how
  many run.
- Agents' reports are claims: check one or two of their VM checks yourself
  on the merged build.

## One source tree, three targets

A single Makefile can detect the platform. Check in this order and stop at the first match:

1. `uname -s` is `Haiku`: Haiku/Renku. Link `-lbe -ltracker -ltranslation`, resources via `rc` and `xres`.
2. `pkg-config --exists vos`, or `$(VOS_HEADERS)/os/BeBuild.h` exists: VitruvianOS (details in vitruvianos.md).
3. `$(COSMOE_ROOT)/include/os/app/Application.h` exists: Cosmoe (details in cosmoe-linux.md).
4. Otherwise print what's needed and fail. The portable unit tests should still build anywhere.

Keep `CXXFLAGS` additive (`override CXXFLAGS +=`) so packagers can pass hardening flags. `templates/Makefile` implements all of this (onboard.md §3).

## Releasing

`references/release.md` is the procedure: onboard once, host checks, push and CI, README screenshots, the final build of all six packages from one commit, a test of every artifact on its platform, notes and `SHA256SUMS`, then `scripts/release-gate.sh`. When it prints `GATE PASSED`, stop and wait for the human to say "publish".

## Platform cheat sheet

| | Renku OS / Haiku | VitruvianOS | Linux (Cosmoe) |
|---|---|---|---|
| Command key | **Alt** | **Ctrl** | **Ctrl** |
| Install | `pkgman install ./x.hpkg` | `sudo apt install ./x.deb` | AppImage: `chmod +x`, run |
| System apps | `/boot/system/apps` | `/system/apps` | inside the AppImage |
| Attributes | BFS, indexable; `listattr`, `query` | `user.beos.*` xattrs (**dpkg drops them**) | `user.*` xattrs, plus `user.COSMOE:ATTR_TYPES` |
| Queries | yes (`mkindex` / `fs_create_index`) | not yet | upstream no; Hokku: yes, from a list of the files with attributes, or by walking the home folder |
| Trash | `/boot/trash` + `_trk/original_path` attr | `~/config/data/Trash/{files,info}` (XDG layout) | `~/.local/share/Trash/{files,info}` |
| `B_USER_SETTINGS_DIRECTORY` | `~/config/settings` | `~/config/settings` | `~/.config/cosmoe` |
| Node monitor | Haiku ints, leaf `name` | `virtual:*` node_ref / entry_refs | **full-path** `name`; upstream Cosmoe: only `watch_path()` works and fields are dev_t/ino_t-typed (both fixed in Hokku) |
| `entry_ref::name` | leaf | leaf | **full path** |
| Open folder/URL | `be_roster->Launch` | `be_roster->Launch` | `xdg-open` |
| Underline/strikeout faces | drawn | drawn | drawn in Hokku (upstream Cosmoe: not drawn) |

## A quick smoke test (outside a release)

Install the package, launch it from a terminal with stdout/stderr going to a log (it should stay empty), check it appears where users start apps and that its signature survived packaging, then exercise what differs per platform: file chooser, drag and drop, Trash, attributes and queries, renames from outside the app (node monitoring), opening links. Check results on disk rather than on screen, and at the VM's resolution (Haiku-family 1024×768). For a release, release-test.md does this in full.
