---
name: beos-app-platforms
description: Build, package, test and release BeOS-style apps (C++ against the Be/Haiku API) for Renku OS (the Haiku fork; .hpkg), VitruvianOS (Haiku API on Linux; .deb) and plain Linux through the Cosmoe library (AppImage). Covers one source tree for all three, Makefile platform detection, packaging, CI builds, and testing in headless VirtualBox VMs (keyboard, mouse, screenshots, SSH) or under Xvfb. Use this whenever the task involves building, porting or packaging a Haiku-API app for any of these systems, cutting or verifying a release, booting or driving a test VM, checking that an app runs on Renku/VitruvianOS/Linux, or reporting a platform bug upstream, even if the user just says "test it on Renku", "make a release", "does it still work on V\OS", "port it to Linux" or "check the AppImage".
---

# Building and testing BeOS-style apps on Renku OS, VitruvianOS and Linux (Cosmoe)

A BeOS-style app is C++ written against the Be/Haiku API (BApplication, BWindow, BView, the storage kit, node monitoring, attributes, Tracker). One source tree can ship on three platforms:

| Platform | What it is | Package | Built where | Tested how |
|---|---|---|---|---|
| **Renku OS** | Fork of Haiku; still names its system package `haiku`, version `r1~beta6` | `.hpkg` (`package create`) | Inside a Haiku-family VM, over SSH | VirtualBox VM: keyboard, mouse, screenshots |
| **VitruvianOS** (V\OS) | Haiku API on a Linux kernel, Debian userland | `.deb` installing to `/system/apps`, **amd64 and arm64** | In CI, natively per architecture, with a link-time SDK | VirtualBox VM (UEFI; amd64 only) |
| **Linux** | Any desktop, through the Cosmoe library | AppImage | **CI** (Ubuntu 24.04) for releases; locally only for porting | Xvfb + Openbox, driven with xdotool |

Read the reference file for what you're doing:

- `references/renku.md`: Renku OS (and Haiku-family guests in general): VM, SSH, building and checking an `.hpkg`, tests
- `references/vitruvianos.md`: VitruvianOS: the SDK, `.deb` packaging (attributes need special handling), VM, tests
- `references/cosmoe-linux.md`: Linux / Cosmoe: porting traps, the Makefile branch, AppImage bundling, CI, headless tests
- `references/virtualbox.md`: driving any VM: scancodes, mouse via the VirtualBox SDK, screenshots, files in and out
- `references/folio.md`: worked example: how the Folio notebook app (github.com/idumych/folio) does all of the above. Its build scripts are good templates for a new app.

Helper scripts in `scripts/` (read each script's header first):

- `make-vm.sh NAME IMAGE [efi]`: create and boot a VM from a copy of an ISO or raw image
- `vm.sh STEP…`: drive a VM (`VM=name`): `k:` scancodes, `t:` text, `m:` mouse, `w:` wait, `shot:` screenshot
- `mouse.py`: absolute mouse input through `vboxapi` (needs the `virtualbox-sdk` package)
- `xtest.sh STEP…`: drive a Cosmoe app under Xvfb (`APP=`, `APP_NAME=`; `start`, held clicks, keys, screenshots)
- `serve-ssh-setup.sh`: one-time key-only SSH setup for a Haiku-family guest
- `redactshot.py`: screenshot with private areas (account IDs, keys) blacked out before anything is written to disk

## Rules that matter

- **Never contact the Haiku project** (no Trac tickets, patches or forum posts), even for bugs that Renku or Cosmoe inherited from Haiku: the user says Haiku doesn't welcome AI contributions. Upstream reports go to **RenkuOS/Source** (AI-assisted work is explicitly allowed; keep write-ups short and plain) and **haydentech/cosmoe**. File only after reproducing the bug in the platform's own code or bundled apps, not just in your app.
- **Build release packages in CI, not against the user's local libraries,** unless the user says otherwise (V\OS `.deb`s: vitruvianos.md; AppImages: cosmoe-linux.md).
- **Target amd64 and arm64 for VitruvianOS** by default: one `deb.yml` job per architecture on `ubuntu-24.04` / `ubuntu-24.04-arm` in `debian:trixie` (haiku-onboard's templates do this). arm64 gets static checks, since VirtualBox can't run arm64 guests on x86.
- **Linux means X11 and Wayland:** Cosmoe picks its backend from `WAYLAND_DISPLAY` / `COSMOE_BACKEND`; the AppImage bundles both, and `appimage.yml` smoke-tests it on a headless Weston (cosmoe-linux.md).
- **Test the exact artifact you publish.** Build every package from one commit. Download the CI AppImage rather than testing a local build. Inside the VMs, install from the release URLs, and compare checksums.
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

Keep `CXXFLAGS` additive (`override CXXFLAGS +=`) so packagers can pass hardening flags.

## The release workflow

1. **Bump the version** everywhere it's written: the `.rdef` `app_version`, each packaging script, the Debian changelog, and file names in the README. Then `git grep` for the old version.
2. **Run checks on the host:** unit tests; a type-check against real Haiku headers; a VitruvianOS SDK link.
3. **Commit, push, and start the AppImage CI** (`gh workflow run <file>.yml --ref main`). Wait for it with `gh run watch <id> --exit-status` in the background.
4. **Build the `.deb` and `.hpkg`** from the same commit: `git archive HEAD | ssh <guest> '… make hpkg'`.
5. **Test every artifact** on its platform, using the checklists in the reference files.
6. **Publish:** `sha256sum … > SHA256SUMS`; create an annotated tag and push it; `gh release create … --verify-tag`. Make the tag-triggered CI leave an AppImage that's already attached alone, so `SHA256SUMS` stays true.
7. **Re-test from the release:** `curl` the release URLs inside each VM.

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
| Node monitor | Haiku ints, leaf `name` | `virtual:*` node_ref / entry_refs | dev_t/ino_t-typed fields, **full-path** `name`; only `watch_path()` works |
| `entry_ref::name` | leaf | leaf | **full path** |
| Open folder/URL | `be_roster->Launch` | `be_roster->Launch` | `xdg-open` |
| Underline/strikeout faces | drawn | drawn | **not drawn** (and picks a different style) |

## A smoke test for any app

1. Install the package the user would install, from the release URL.
2. Launch it from a terminal with stdout/stderr going to a log. The log should stay empty.
3. Check that it appears where users start apps (the Deskbar menu, `.desktop`), and that the app's attributes or signature survived packaging.
4. Exercise the features that touch platform differences: file chooser, drag and drop, Trash, attributes and queries, renames from outside the app (node monitoring), opening links.
5. Check results on disk (`grep`, `listattr`/`getfattr`, `ls`) rather than trusting the screen.
6. Test at the VM's resolution (Haiku-family 1024×768): windows must stay on screen.
