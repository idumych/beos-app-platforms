# beos-app-platforms

A [Claude Code](https://claude.com/claude-code) skill (also usable from opencode) for building, packaging, testing and releasing **BeOS-style apps**, that is, C++ written against the Be/Haiku API, on three platforms from one source tree:

| Platform | Package | Tested in |
|---|---|---|
| [Renku OS](https://github.com/RenkuOS/Source) (Haiku fork), Haiku R1/beta6 | `.hpkg`, x86_64 (arm64 has no target yet), built in a Haiku R1/beta6 VM | VirtualBox VM |
| [VitruvianOS](https://v-os.dev) (a BeOS-like OS based on Linux) | `.deb` (amd64, arm64) | VirtualBox VM (amd64); static checks (arm64) |
| Linux, through [Hokku](https://github.com/idumych/hokku) (a fork of [Cosmoe](https://github.com/haydentech/cosmoe)) | AppImage, x86_64 and aarch64 (X11 and Wayland) | Xvfb + Openbox (X11); X11 and headless sway in CI on both architectures |

It records what was learned shipping [Folio](https://github.com/idumych/folio) and [Sheath](https://github.com/idumych/sheath) on all three:
- **Porting:** the Makefile platform branches, plus the traps on each system (node monitoring, attributes, Trash, `entry_ref` names, font faces picked by style name, tooltips that never hide on Cosmoe, headers missing from R1/beta6).
- **Packaging for amd64 and arm64:** the `.hpkg` in a Haiku R1/beta6 VM (or on a GitHub runner with `cross-platform-actions`), x86_64 until Haiku has an arm64 target; the VitruvianOS `.deb` for **amd64 and arm64**, built natively per architecture in `debian:trixie` (with the attribute workaround); and a relocatable AppImage for **x86_64 and aarch64** that bundles both Cosmoe backends and is started under X11 and Wayland on each architecture in CI.
- **Testing:** driving VMs headlessly, with keyboard scancodes, mouse input through the VirtualBox SDK (hovering before menu clicks), screenshots read with OCR, and one-time SSH into Haiku-family guests; Cosmoe builds under Xvfb on a display of your choice; and a **Wayland** smoke test on headless sway with `grim` screenshots (headless Weston has no seat, so Cosmoe apps quit there).
- **Releases:** a complete pipeline: onboarding templates for any app (`haiku-app.env`, Makefile, packaging, CI), a build of all three from one commit, a scripted test of each package on its platform with evidence files, and a release gate that checks the raw evidence and stops for a human before anything is published. Written so that an agent, including a local model, can release an app unsupervised.
- **Hokku:** Linux builds use [Hokku](https://github.com/idumych/hokku), a Cosmoe fork that takes AI-generated fixes and aims to be a library freestanding Renku/Haiku app ports can build against. Cosmoe bugs get fixed there, not worked around in each app; Cosmoe itself doesn't accept AI contributions.
- **Upstream reports:** where they go and how to write them.

## Install

Clone it into your personal skills folder, and Claude Code picks it up in every project:

```sh
git clone https://github.com/idumych/beos-app-platforms.git ~/.claude/skills/beos-app-platforms
```

Or, to share it with one project's collaborators, put it in that project's `.claude/skills/beos-app-platforms/`.

Claude loads it when a task involves building, porting, packaging, releasing or VM-testing a Haiku-API app, for example "test it on Renku", "make a release" or "check the AppImage".

## Contents

| File | What |
|---|---|
| `SKILL.md` | Overview, ground rules, Makefile platform detection, platform cheat sheet, where to start a release |
| `references/release.md` | The release procedure: phases, building (`.hpkg` in a VM, `.deb`s and AppImage in CI), release notes, publishing, rules |
| `references/onboard.md` | Setting an app up for releases: `haiku-app.env`, the Makefile contract, templates, the app's test plan |
| `references/release-test.md` | Testing each package on its platform and writing the evidence; the shared test VMs |
| `references/renku.md` | Renku OS / Haiku-family: VM, SSH, building the `.hpkg` in CI or a VM, checking it, tests |
| `references/vitruvianos.md` | VitruvianOS: amd64/arm64 SDK and CI, `.deb` packaging, VM, tests |
| `references/cosmoe-linux.md` | Hokku/Cosmoe: using and fixing Hokku, porting traps, Makefile branch, AppImage recipe, CI, headless X11 and Wayland testing |
| `references/virtualbox.md` | Driving VMs: scancodes, mouse (hover before menu clicks), screenshots, moving files |
| `references/folio.md` | Worked example: Folio, an app set up with the templates |
| `scripts/make-vm.sh` | Create and boot a test VM from a copy of an ISO or raw image |
| `scripts/vm.sh`, `scripts/mouse.py` | Drive a VM: keys, text, mouse, screenshots |
| `scripts/xtest.sh` | Drive a Cosmoe app under Xvfb (`XDISPLAY` picks the display), kept away from your real desktop |
| `scripts/serve-ssh-setup.sh` | One-time key-only SSH setup for a Haiku-family guest |
| `scripts/redactshot.py` | Screenshots with private areas blacked out before they reach disk |
| `scripts/ocr-find.sh` | A screenshot as text, with click positions |
| `scripts/check-artifact.sh`, `scripts/release-gate.sh` | Static package checks; the final yes/no for a release |
| `templates/` | Copied into an app by onboarding: `haiku-app.env`, `Makefile`, `packaging/`, `.github/workflows/`, `tools/` |

**Requirements** for the scripts: VirtualBox 7 with its SDK (`vboxapi`, for mouse input); `xorg-server-xvfb`, `openbox`, `xdotool` and ImageMagick for headless Cosmoe tests; `tesseract` for `ocr-find.sh`; `dpkg` for the package checks; and `gh` for releases and CI. The Wayland test (sway, grim) and the arm64 builds run on GitHub's runners, so the host needs neither.

The scripts have been used with Arch-based hosts (CachyOS) and VirtualBox 7.2. `make-vm.sh` and `serve-ssh-setup.sh` are newer versions of steps that were first run by hand.

## Licence

MIT. See [LICENSE](LICENSE).
