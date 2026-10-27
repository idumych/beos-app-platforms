# beos-app-platforms

A [Claude Code](https://claude.com/claude-code) skill (also usable from opencode) for **BeOS-style apps**: C++ written against the Be/Haiku API (BApplication, BWindow, the storage, interface and media kits). It covers the whole life of such an app: porting it to the native API, building one source tree for several systems, testing every package on the system it's for, and releasing it, with a human sign-off before anything is published.

It's written as instructions an agent follows, with scripts and templates beside them, so a model (a local one included) can do this work largely unsupervised, and stop where it should.

## What it's for

| Job | What the skill provides |
|---|---|
| **Porting** an app to the native Haiku API, from Qt, GTK, SDL or a Linux-only stack | A check that nobody has ported it already; reference screenshots of the original before any UI code, measured and compared after every change; a portable core with no Haiku headers; the API traps; a vector icon encoder; UI tests through `hey` scripting. For audio apps, a Media Kit filter node between the system mixer and the sound card |
| **Building** one tree for several systems | Makefile platform detection, a `-DAPP_COSMOE` style switch for the few real differences, and the porting traps of each system |
| **Testing** every package where it will run | Headless VMs (VirtualBox or QEMU/KVM) driven by keyboard, mouse, screenshots, OCR and SSH; Linux builds under Xvfb; X11 and Wayland smoke tests in CI on x86_64 and aarch64; audio checked from a capture of the guest's sound card |
| **Theming** the system: window decorators, control looks, colours and fonts | How app_server decorator add-ons and libbe control looks are built and what they can't do, a theme tool that saves and restores the previous look, and shipping one look to many Renku and Haiku builds as a zip that compiles on the target |
| **Releasing** | Onboarding templates for any app, a build of every package from one commit, a scripted test of each with evidence files, and a release gate that checks the raw evidence and then stops for a human |

Claude loads it when a task involves building, porting, packaging, releasing or VM-testing a Haiku-API app, for example "is it worth porting X to Renku?", "port this to the native Haiku UI", "test it on Renku", "make a release", "make a window decorator" or "check the AppImage".

## Platforms

| Platform | Package | Built | Tested |
|---|---|---|---|
| [Renku OS](https://github.com/RenkuOS/Source) (a Haiku fork) and [Haiku](https://www.haiku-os.org) R1/beta6, x86_64 | `.hpkg`; one package installs on both (Renku still calls its system package `haiku r1~beta6`) | In a Haiku R1/beta6 VM, on a GitHub runner, or on Renku itself | In a VM: installed, launched, driven, read back from disk |
| Haiku arm64 | `.hpkg`, for apps that use only Haiku's own libraries | Cross-built on Linux (there is no R1/beta6 or HaikuPorts arm64 repository yet; the skill says how to check at each release) | On an arm64 nightly in QEMU |
| Linux, through [Hokku](https://github.com/idumych/hokku) (a fork of [Cosmoe](https://github.com/haydentech/cosmoe)) | AppImage, x86_64 and aarch64, bundling both the X11 and the Wayland backend | Natively per architecture in GitHub CI, on the oldest supported distro | Full test under Xvfb; started under X11 and headless Wayland on both architectures in CI |

## Ground rules it enforces

- **Look for an existing port before starting a new one**, and let the user decide what to do with what turns up.
- **Platform bugs go to Renku OS, Cosmoe bugs are fixed in Hokku**, never reported to Haiku or Cosmoe, which don't accept AI-generated contributions. File only after reproducing the bug in the platform's own code.
- **Test the exact files that will be published**, built from one commit, and publish only after the gate passes and a human says so.
- **Report honestly**: "type-checked" isn't "ran", a headless X11 run isn't a Wayland run, and a QEMU sound card isn't real hardware.
- **Never type or capture the user's secrets** in a VM; redact screenshots that could show them.

## Challenges it has worked through

Each of these cost real time once, and is now a paragraph, a check or a script.

**Porting**
- Native ports drifted from the original's look (a tool box half again too wide, the wrong button style). Now: collect or take screenshots of the original first, measure them with PIL, and compare side by side after every UI build.
- API traps that compile but misbehave: views added to a layout with no owner never exist; `BTextControl` sends its change message for programmatic `SetText`, so linked fields ping-pong; `BSpinner` is private; `BAboutWindow` isn't in beta6's headers; a `BBitmap` without a `BApplication` hangs.
- Cosmoe differences that break apps quietly: `entry_ref::name` and node-monitor names are full paths, attributes become `user.*` xattrs, there are no queries, the Trash is the freedesktop one. Bugs found there (node monitor field types, undrawn underline faces) were fixed in Hokku, not worked around in each app.
- Linux audio apps have no PipeWire on Haiku: a system-wide effect has to be a Media Kit node spliced between the system mixer and the sound card. The system mixer only auto-starts the node it feeds, so a filter there must start the output itself, or the result is silence with no error. Found by reading each node's clock.

**Building and packaging**
- AppImages built on an Arch/CachyOS host crashed on older CPUs (x86-64-v3 code) and wouldn't start on Ubuntu 24.04 (newer glibc). Releases are built in CI on the oldest supported distro.
- No arm64 Haiku release to build on: apps that use only Haiku's libraries are cross-built against a sysroot made from the master arm64 repository and tested on a nightly in QEMU.
- Renku's `haiku_devel` lagged its nightly, and installing it meant a system downgrade and a reboot. The skill extracts it beside the toolchain instead, with the exact compiler flags (`-B`, and `-idirafter`, because libstdc++'s `#include_next` fails with `-isystem`).
- Resources stripped off binaries (strip at link time: `xres` appends after the ELF data); `.PackageInfo` details that make one package install on both Haiku and Renku.

**Testing**
- Haiku-family guests hung on the boot splash, with media_server crash-looping in `runtime_loader`. It looked like a VirtualBox bug. It isn't: QEMU does the same, and on Renku build00064 a freshly copied image boots while every later boot of it hangs. The skill says how to tell (serial log, kernel debugger) and how to work around it.
- VMs with a PS/2 pointer ignore absolute clicks: UI tests send mouse messages straight to the app's views with `hey`. Menus need a hover before the click; Haiku's screen blanker ate the first typed letter; OCR misses window titles.
- VirtualBox with the ALSA driver hung on power-off on a PipeWire host; KVM fails outright while any VirtualBox VM runs.
- Headless Weston has no seat, so Cosmoe apps quit there; the Wayland test uses headless sway with `grim` screenshots, and fails on a blank screen or a window that never appears.
- Audio checks from QEMU's capture of the guest's sound card: the rate conversion leaves single-sample kinks that a naive click counter reports as glitches with or without the code under test. The checker counts only real dropouts (phase jumps, silence), and judges a node only against runs without it on the same host.
- Smaller things with outsized cost: `pkill -f` matching its own command line; `gh` in a fork looking at the upstream repository's CI; `Ctrl/Alt+A` selecting the document instead of a field.

**Theming**
- A window decorator runs inside app_server and links against its binary, so it is tied to that build's private ABI, and a crash takes the desktop down. An `.hpkg` would have to pin the exact `haiku` version. Instead the decorator and control look interfaces were checked to be unchanged from Haiku R1/beta6 to current Renku, the 54 private headers they need are bundled, and a zip's `install.sh` builds them on the target into `~/config/non-packaged`. Every install script and README gives the safe-mode way back ("Disable user add-ons").
- Overwriting an add-on that apps have mapped crashed them; installs now copy to `.new` and rename. `pkgman install` of the same version silently did nothing, so screenshots showed the old build; now uninstall first and compare checksums.
- Drawing traps: app_server's `Window.h` shadowing the kit's (use `-iquote`); `TabDecorator` moving custom tab buttons back; highlighted menu labels drawn invisibly without `PushState`/`PopState`; layouts shifting when a control look changes Haiku's frame insets; a theme tool saving default colours because it had no `BApplication`.
- An app_server bug: windows open during a decorator switch keep the old content region until resized (`Window::ReloadDecor()` doesn't reset `fContentRegionValid`).

**Releasing**
- Releases that claimed more than was tested. Now every package writes an evidence file, the gate script reads only raw evidence, the release notes' "Tested" section must match it, and the pipeline stops for a human before publishing, then re-tests from the release URLs.

## Apps it has been used on

- [Folio](https://github.com/idumych/folio), a notebook app: onboarded with the templates, shipped for Haiku/Renku and Linux.
- [Sheath](https://github.com/idumych/sheath): the `.hpkg` built and tested in GitHub CI with no local VM.
- [EasyPaint](https://github.com/idumych/EasyPaint) (branch `haiku-native`): a Qt 5 paint program ported to the native API and released.
- [Gonx](https://github.com/idumych/gonx): a full system look (decorator, control look, colours, fonts) for Renku and Haiku from a 2001 BeOS concept, released as a zip that builds on the target and tested on both.
- JamesDSP for Linux: evaluated for Renku; its DSP engine runs as a Media Kit node in a Renku VM (a proof of concept, not a release).

## Install

Clone it into your personal skills folder, and Claude Code picks it up in every project:

```sh
git clone https://github.com/idumych/beos-app-platforms.git ~/.claude/skills/beos-app-platforms
```

Or, to share it with one project's collaborators, put it in that project's `.claude/skills/beos-app-platforms/`.

## Contents

| File | What |
|---|---|
| `SKILL.md` | Overview, ground rules, Makefile platform detection, platform cheat sheet, where to start |
| `references/porting.md` | Porting to the native API: the existing-port check, reference screenshots, structure, API traps, icons, `hey`-driven tests |
| `references/media-kit.md` | Audio apps: a filter node between the mixer and the sound card, its traps, end-to-end audio tests |
| `references/release.md` | The release procedure: phases, building, release notes, publishing |
| `references/onboard.md` | Setting an app up for releases: `haiku-app.env`, the Makefile contract, templates, the app's test plan |
| `references/release-test.md` | Testing each package on its platform and writing the evidence; the shared test VM |
| `references/renku.md` | Renku OS and Haiku guests: VMs (VirtualBox or QEMU), the boot hang, SSH, building on Renku, the `.hpkg`, CI builds, arm64 status, bug reports |
| `references/haiku-arm64.md` | The arm64 `.hpkg`: cross toolchain and sysroot, the QEMU test machine, what can't be built yet |
| `references/cosmoe-linux.md` | Hokku/Cosmoe: using and fixing Hokku, porting traps, the AppImage, CI, headless X11 and Wayland tests |
| `references/virtualbox.md` | Driving VMs: scancodes, mouse, screenshots, files, hangs |
| `references/theming.md` | System looks: window decorators, control looks, colours and fonts; one look for many Renku/Haiku builds; cross-building and deploying; comparing against reference art |
| `references/folio.md` | Worked example: an app set up with the templates |
| `scripts/make-vm.sh`, `scripts/vm.sh`, `scripts/mouse.py` | VirtualBox: create a VM from an image; keys, text, mouse, screenshots |
| `scripts/qemu-vm.sh`, `scripts/qmp-input.py` | QEMU/KVM x86_64 VM: create, start, keys, pointer, screenshots, the guest's audio to a WAV file |
| `scripts/haiku-arm64-vm.sh` | A Haiku arm64 nightly in QEMU |
| `scripts/serve-ssh-setup.sh` | One-time key-only SSH setup for a Haiku-family guest |
| `scripts/hey-ui.sh` | Mouse messages and commands to an app's views with `hey`, for VMs where clicks don't work |
| `scripts/tone.cpp`, `scripts/sine-check.py` | Play a test tone through the system mixer; measure its level and dropouts in the capture |
| `scripts/xtest.sh` | Drive a Cosmoe app under Xvfb, away from your real desktop |
| `scripts/make-hvif-icon.py` | Encode a vector app icon (HVIF) as an `.rdef` resource, with an SVG preview |
| `scripts/redactshot.py`, `scripts/ocr-find.sh` | Screenshots with private areas blacked out; a screenshot as text with click positions |
| `scripts/check-artifact.sh`, `scripts/release-gate.sh` | Static package checks; the final yes/no for a release |
| `templates/` | Copied into an app by onboarding: `haiku-app.env`, `Makefile`, `packaging/`, `.github/workflows/`, `tools/` |

**Requirements** for the scripts: VirtualBox 7 with its SDK (`vboxapi`) or QEMU with KVM, plus `socat`; ImageMagick; `xorg-server-xvfb`, `openbox` and `xdotool` for headless Cosmoe tests; `tesseract` for `ocr-find.sh`; Python 3 with PIL and NumPy; `qemu-user` or `squashfs-tools` to unpack an aarch64 AppImage on an x86 host; and `gh` for releases and CI. The Wayland tests and the aarch64 builds run on GitHub's runners, so the host needs none of that.

The scripts have been used on Arch-based hosts (CachyOS) with VirtualBox 7.2 and QEMU 11.

## Known open issues

- Renku build00064 hangs on every boot after the first; test VMs are recopied per boot until that's fixed.
- Apps that need HaikuPorts libraries can't ship arm64 `.hpkg`s until HaikuPorts has an arm64 repository.
- The JamesDSP node showed occasional dropouts in QEMU when the host was busy; whether the node is the cause hasn't been settled.

## Licence

MIT. See [LICENSE](LICENSE).
