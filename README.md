# beos-app-platforms

A [Claude Code](https://claude.com/claude-code) skill for building, packaging, testing and releasing **BeOS-style apps**, that is, C++ written against the Be/Haiku API, on three platforms from one source tree:

| Platform | Package | Tested in |
|---|---|---|
| [Renku OS](https://github.com/RenkuOS/Source) (Haiku fork), Haiku R1/beta6 | `.hpkg`, built in GitHub CI on Haiku R1/beta6 | VirtualBox VM |
| [VitruvianOS](https://v-os.dev) (Haiku API on Linux) | `.deb` (amd64, arm64) | VirtualBox VM (amd64); static checks (arm64) |
| Linux, through [Hokku](https://github.com/idumych/hokku) (a fork of [Cosmoe](https://github.com/haydentech/cosmoe)) | AppImage (X11 and Wayland) | Xvfb + Openbox (X11); headless sway in CI (Wayland) |

It records what was learned shipping [Folio](https://github.com/idumych/folio) and [Sheath](https://github.com/idumych/sheath) on all three:
- **Porting:** the Makefile platform branches, plus the traps on each system (node monitoring, attributes, Trash, `entry_ref` names, font faces picked by style name, tooltips that never hide on Cosmoe, headers missing from R1/beta6).
- **Packaging, all in CI:** the `.hpkg` in a Haiku R1/beta6 VM on a GitHub runner (`cross-platform-actions`); the VitruvianOS `.deb` for **amd64 and arm64**, built natively per architecture in `debian:trixie` (with the attribute workaround); and a relocatable AppImage that bundles both Cosmoe backends.
- **Testing:** driving VMs headlessly, with keyboard scancodes, mouse input through the VirtualBox SDK (hovering before menu clicks), screenshots read with OCR, and one-time SSH into Haiku-family guests; Cosmoe builds under Xvfb on a display of your choice; and a **Wayland** smoke test on headless sway with `grim` screenshots (headless Weston has no seat, so Cosmoe apps quit there).
- **Releases:** README screenshots from the release candidate on every platform, committed before the final build.
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
| `SKILL.md` | Overview, ground rules, Makefile platform detection, release workflow, platform cheat sheet, smoke test |
| `references/renku.md` | Renku OS / Haiku-family: VM, SSH, building the `.hpkg` in CI or a VM, checking it, tests |
| `references/vitruvianos.md` | VitruvianOS: amd64/arm64 SDK and CI, `.deb` packaging, VM, tests |
| `references/cosmoe-linux.md` | Hokku/Cosmoe: using and fixing Hokku, porting traps, Makefile branch, AppImage recipe, CI, headless X11 and Wayland testing |
| `references/virtualbox.md` | Driving VMs: scancodes, mouse (hover before menu clicks), screenshots, moving files |
| `references/folio.md` | Worked example: Folio's files as templates |
| `scripts/make-vm.sh` | Create and boot a test VM from a copy of an ISO or raw image |
| `scripts/vm.sh`, `scripts/mouse.py` | Drive a VM: keys, text, mouse, screenshots |
| `scripts/xtest.sh` | Drive a Cosmoe app under Xvfb (`XDISPLAY` picks the display), kept away from your real desktop |
| `scripts/serve-ssh-setup.sh` | One-time key-only SSH setup for a Haiku-family guest |

**Requirements** for the scripts: VirtualBox 7 with its SDK (`vboxapi`, for mouse input); `xorg-server-xvfb`, `openbox`, `xdotool` and ImageMagick for headless Cosmoe tests; and `gh` for releases and CI. The Wayland test (sway, grim) and the arm64 builds run on GitHub's runners, so the host needs neither.

The full release pipeline (onboarding templates, artifact checks and the release gate) lives in the companion `haiku-*` skills; this one holds the platform knowledge they rely on.

The scripts have been used with Arch-based hosts (CachyOS) and VirtualBox 7.2. `make-vm.sh` and `serve-ssh-setup.sh` are newer versions of steps that were first run by hand.

## Licence

MIT. See [LICENSE](LICENSE).
