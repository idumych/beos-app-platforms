# beos-app-platforms

A [Claude Code](https://claude.com/claude-code) skill for building, packaging, testing and releasing **BeOS-style apps**, that is, C++ written against the Be/Haiku API, on three platforms from one source tree:

| Platform | Package | Tested in |
|---|---|---|
| [Renku OS](https://github.com/RenkuOS/Source) (Haiku fork) | `.hpkg` | VirtualBox VM |
| [VitruvianOS](https://v-os.dev) (Haiku API on Linux) | `.deb` | VirtualBox VM |
| Linux, through [Cosmoe](https://github.com/haydentech/cosmoe) | AppImage | Xvfb + Openbox, headless |

It records what was learned shipping [Folio](https://github.com/idumych/folio) on all three:
- **Porting:** the Makefile platform branches, plus the traps on each system (node monitoring, attributes, Trash, `entry_ref` names, font faces).
- **Packaging:** recipes for `.hpkg`, `.deb` (with the attribute workaround) and a relocatable AppImage built in CI.
- **Testing:** driving VMs headlessly, with keyboard scancodes, mouse input through the VirtualBox SDK, screenshots and one-time SSH into Haiku-family guests, plus testing Cosmoe builds under Xvfb.
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
| `references/renku.md` | Renku OS / Haiku-family: VM, SSH, building and checking an `.hpkg`, tests |
| `references/vitruvianos.md` | VitruvianOS: SDK, `.deb` packaging, VM, tests |
| `references/cosmoe-linux.md` | Cosmoe: porting traps, Makefile branch, AppImage recipe, CI, headless testing |
| `references/virtualbox.md` | Driving VMs: scancodes, mouse, screenshots, moving files |
| `references/folio.md` | Worked example: Folio's files as templates |
| `scripts/make-vm.sh` | Create and boot a test VM from a copy of an ISO or raw image |
| `scripts/vm.sh`, `scripts/mouse.py` | Drive a VM: keys, text, mouse, screenshots |
| `scripts/xtest.sh` | Drive a Cosmoe app under Xvfb, kept away from your real desktop |
| `scripts/serve-ssh-setup.sh` | One-time key-only SSH setup for a Haiku-family guest |

**Requirements** for the scripts: VirtualBox 7 with its SDK (`vboxapi`, for mouse input); `xorg-server-xvfb`, `openbox`, `xdotool` and ImageMagick for headless Cosmoe tests; and `gh` for releases and CI.

The scripts have been used with Arch-based hosts (CachyOS) and VirtualBox 7.2. `make-vm.sh` and `serve-ssh-setup.sh` are newer versions of steps that were first run by hand.

## Licence

MIT. See [LICENSE](LICENSE).
