# Driving VirtualBox VMs headlessly

Everything here works with the VM running `--type headless`, so the user's desktop isn't disturbed. The user may also open a VM window in the VirtualBox GUI. If a VM suddenly reports "not currently running", check `VBoxManage showvminfo <vm> --machinereadable | grep VMState` and the end of `~/VirtualBox VMs/<vm>/Logs/VBox.log`. "SUSPENDED → POWERING_OFF" with no guest error means it was closed from the host side, probably the user. Ask before restarting it again.

## Know which VMs are yours to drive

Run `VBoxManage list vms` and `list runningvms` before doing anything. Only drive VMs created for testing (a `<app>-<platform>` naming scheme helps), and never touch the user's own VMs. A typical set:

| VM | Image | Notes |
|---|---|---|
| `<app>-renku` | Renku nightly ISO | BIOS, 1024×768 |
| `<app>-haiku` | Haiku R1/beta6 anyboot (+ a work disk) | SSH on 127.0.0.1:2222; gcc, make, haiku_devel; builds the hpkg |
| `<app>-vos` | VitruvianOS raw image | UEFI, 1280×800, live user `vos-live` |

Keep the machine-specific list (names, SSH aliases, what's installed) in project memory or notes, not in this skill.

## Create a VM

```sh
sh scripts/make-vm.sh NAME IMAGE [efi]
```

It converts a copy of the ISO or raw image to VDI (`convertfromraw`; never edits the original), gives the VM 4 GB RAM, 4 CPUs, NAT, a USB tablet (for absolute mouse positions), no audio, and VBoxSVGA (VMSVGA for EFI), then boots it headless. Use `efi` for UEFI-only images (VitruvianOS). Haiku-family anyboot ISOs boot with BIOS.

## Keyboard: `scripts/vm.sh`

```sh
VM=folio-renku sh scripts/vm.sh "t:some text" k:1c,9c w:2 shot:name
```

- `t:` uses `keyboardputstring`. It types fast in most guests, but slowly into a Haiku Terminal (about 30 characters a second).
- `k:` sends raw set-1 scancodes. A press is the code; the release is the code + 0x80. Common ones:

| Key | Press,release | Key | Press,release |
|---|---|---|---|
| Enter | `1c,9c` | Esc | `01,81` |
| Backspace | `0e,8e` | Tab | `0f,8f` |
| Ctrl (left) | `1d … 9d` | Alt (left) | `38 … b8` |
| End | `e0,4f,e0,cf` | Down | `e0,50,e0,d0` |
| Q `10` · W `11` · E `12` · R `13` · T `14` · I `17` | | F1 `3b` · F2 `3c` | |

  Chords: Ctrl+R = `k:1d,13,93,9d`; Alt+R = `k:38,13,93,b8`; Ctrl+End = `k:1d,4f,cf,9d`. Some guests read plain `4f` as End.
- `shot:name` saves `$SCRATCH/name.png`. Read the PNG to see the screen. Always take a screenshot before clicking somewhere new: window positions differ between boots and window managers.

## Mouse: `scripts/mouse.py` (also `m:` in vm.sh)

This needs the `virtualbox-sdk` package (Arch: `pacman -S virtualbox-sdk`, matching the VirtualBox version), which provides the Python `vboxapi`. VBoxManage itself has no mouse command.

```sh
VM=<vm> python3 scripts/mouse.py click X Y        # also: rclick, dclick, ctrlclick, altclick, move, drag X Y X2 Y2
```

Coordinates are screenshot pixels. The script holds the button about 80 ms and moves in steps for drags, which suits Tracker drag-and-drop. Before quitting it calls `os._exit(0)`, because vboxapi's teardown prints a harmless traceback otherwise.

## Files in and out

1. **Best:** SSH (Haiku-family; see renku.md), then `scp` or `tar | ssh`.
2. **Published files:** `curl` the GitHub release URL from inside the guest. This is also the truest install test.
3. **From the host:** run `python3 -m http.server PORT --bind <LAN-IP>` in a directory holding only what's needed, and stop it afterwards. Find the LAN IP with `ip route get 1.1.1.1 | grep -oP 'src \K\S+'`. **127.0.0.1 doesn't work:** VirtualBox 7 NAT blocks guest-to-host loopback (`10.0.2.2` gives connection refused). The host's ufw allows this, because NAT traffic comes from the host itself.
4. **Tiny files without networking:** `echo <base64> | base64 -d | tar -xz` typed with `t:`.
5. **Unreleased test builds when 3 is blocked** (auto mode may refuse a LAN server, or an ISO attached as a DVD, as "exposing local services"): tag a release candidate (`v1.2.3-rc1`) so the tag-triggered CI publishes it as a **prerelease**, which never becomes "Latest". Install it from the release URL like a real release, and delete the rc releases and tags once the final is out. `gh release delete <tag> --cleanup-tag` removes the local tag too, so don't `git tag -d` after it in an `&&` chain.

## Driving the user's own VM

When the user asks you to test in a VM they're using:

- **Their host mouse moves the guest pointer** whenever it passes over the VM window in the VirtualBox GUI, and **resizing that window changes the guest resolution**. Clicks then land in the wrong place (a click can become a drag). Re-check the resolution (`PIL.Image.open(shot).size`) and take a screenshot before every click; ask the user to keep the mouse off the window while you work.
- **Windows stack.** A window hidden under another can't be clicked; raise it from its Deskbar entry first (click the app, then the window name in the list that opens).
- **Escape may not close a pop-up menu** in a VitruvianOS app; click an empty spot on the desktop instead, then screenshot before the next step.
- **Passwords:** run the command and stop at the `[sudo] password` prompt; the user types it. `sudo` stays cached for about 15 minutes.
- **Put back what you changed** (settings, connections) and say so.

## Screenshots that must not show private data

`VBoxManage controlvm … screenshotpng` writes the full screen to disk. For apps that show an account ID, e-mail address or key, use `scripts/redactshot.py` instead: it grabs the screen into memory and saves only a redacted copy.

1. Read the app's source to find where the private text is drawn (a label at the bottom of the window, an item in a menu).
2. Before the window's position is known, use `--panel-bottom PX`: it blacks out the bottom PX pixels of each window panel, and blacks out the whole image when it finds none.
3. Once a redacted shot shows where the window sits, add `--fixed X0,Y0,X1,Y1` rectangles: over that area, and over a menu's private item before opening the menu. Be generous; a few lost pixels don't matter.
4. Keep only the shots you need; delete the rest.

## Hygiene

- Shut a guest down from inside (`sync; shutdown` on Haiku-family) before changing VM settings, so installed packages are kept.
- Never `pkill -f <word>` when the word is in your own command line: it kills the shell running it. Use `pkill -x <name>`.
- To remove a test VM: `VBoxManage controlvm <vm> poweroff; VBoxManage unregistervm <vm> --delete`. Ask the user first; they may want to keep it.
