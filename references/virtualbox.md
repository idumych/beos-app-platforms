# Driving VirtualBox VMs headlessly

Everything here works with the VM running `--type headless`, so the user's desktop isn't disturbed. The user may also open a VM window in the VirtualBox GUI. If a VM suddenly reports "not currently running", check `VBoxManage showvminfo <vm> --machinereadable | grep VMState` and the end of `~/VirtualBox VMs/<vm>/Logs/VBox.log`. "SUSPENDED → POWERING_OFF" with no guest error means it was closed from the host side, probably the user. Ask before restarting it again.

## Know which VMs are yours to drive

Run `VBoxManage list vms` and `list runningvms` before doing anything. Only drive VMs created for testing (a `<app>-<platform>` naming scheme helps), and never touch the user's own VMs. A typical set:

| VM | Image | Notes |
|---|---|---|
| `<app>-renku` | Renku nightly ISO | BIOS, 1024×768 |
| `<app>-haiku` | Haiku R1/beta6 anyboot (+ a work disk) | SSH on 127.0.0.1:2222; gcc, make, haiku_devel; builds the hpkg |

Releases use one shared VM, `haiku-b6-test` (release-test.md § Test VM). Keep the machine-specific list (names, SSH aliases, keys, what's installed) in project memory or notes, not in this skill.

## Create a VM

```sh
sh scripts/make-vm.sh NAME IMAGE [efi]
```

It converts a copy of the ISO or raw image to VDI (`convertfromraw`; never edits the original), gives the VM 4 GB RAM, 4 CPUs, NAT, a USB tablet (for absolute mouse positions), no audio, and VBoxSVGA (VMSVGA for EFI), then boots it headless. Use `efi` for UEFI-only images. Haiku-family anyboot ISOs boot with BIOS.

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

- **Menu items need a hover first** (Haiku/Renku): an instant click on an item in a menu
  that just opened is often ignored and the menu stays open. Move onto the item, wait, then
  click: `m:move,X,Y w:0.4 m:click,X,Y`. Submenus the same way: hover the parent item, move
  across into the submenu, hover the item, click.
- **OCR picks the first matching word**, which may be in a status line rather than on the
  button ("download" vs "Download"). Check the y coordinate, or read the screenshot.
- **Absolute clicks need a USB tablet.** `mouse.py` uses absolute events,
  which a VM with `hidpointing="ps2mouse"` ignores: the pointer doesn't
  move. Check with `VBoxManage showvminfo <vm> --machinereadable | grep
  hidpointing`. On your own test VMs set `--mouse usbtablet` (powered off).
  On the user's VM, don't change it without asking; instead:
  - drive the app under test with `hey` (porting.md §6, `scripts/hey-ui.sh`);
  - move the pointer out of a screenshot with relative events, which PS/2
    accepts: `session.console.mouse.putMouseEvent(dx, dy, 0, 0, 0)` in a
    few steps, through a `Shared` session lock;
  - start programs with the keyboard. On Haiku, Ctrl+Esc did *not* open the
    Deskbar menu (beta6); Tracker type-ahead does it: type the name of a
    desktop icon (e.g. `Haiku`, the boot volume), Alt+O to open it, then
    `system`, Alt+O, `apps`, Alt+O, `Terminal`, Alt+O. Alt+O is
    `k:38` … `k:18,98` … `k:b8` with short pauses between.

## Booting a VM that starts from the wrong device

A VM may have a live ISO attached and boot it first. Without changing its
boot order, press F12 (`k:58,d8` repeatedly right after `startvm`) for
VirtualBox's boot menu and press `1` for the first hard disk. Choosing the
disk volume from the *ISO's* Haiku boot loader can fail instead: a Haiku
R1/beta6 install booted through a newer distro ISO's loader (Pirati del
Frico rev10) panicked at once with "Divide Error Exception" in thread 0.
After a panic that early, `VBoxManage controlvm <vm> poweroff` is safe;
nothing is mounted yet.

## Files in and out

1. **Best:** SSH (Haiku-family; see renku.md), then `scp` or `tar | ssh`.
2. **Published files:** `curl` the GitHub release URL from inside the guest. This is also the truest install test.
3. **From the host:** run `python3 -m http.server PORT --bind <LAN-IP>` in a directory holding only what's needed, and stop it afterwards. Find the LAN IP with `ip route get 1.1.1.1 | grep -oP 'src \K\S+'`. **127.0.0.1 doesn't work:** VirtualBox 7 NAT blocks guest-to-host loopback (`10.0.2.2` gives connection refused). The host's ufw allows this, because NAT traffic comes from the host itself.
4. **Tiny files without networking:** `echo <base64> | base64 -d | tar -xz` typed with `t:`.
5. **Unreleased test builds when 3 is blocked** (auto mode may refuse a LAN server, or an ISO attached as a DVD, as "exposing local services"): tag a release candidate (`v1.2.3-rc1`) so the tag-triggered CI publishes it as a **prerelease**, which never becomes "Latest". Install it from the release URL like a real release, and delete the rc releases and tags once the final is out. `gh release delete <tag> --cleanup-tag` removes the local tag too, so don't `git tag -d` after it in an `&&` chain. Auto mode blocks the delete as destructive unless the user has explicitly asked for it, so ask once the final is published.

## Driving the user's own VM

When the user asks you to test in a VM they're using:

- **Their host mouse moves the guest pointer** whenever it passes over the VM window in the VirtualBox GUI, and **resizing that window changes the guest resolution**. Clicks then land in the wrong place (a click can become a drag). Re-check the resolution (`PIL.Image.open(shot).size`) and take a screenshot before every click; ask the user to keep the mouse off the window while you work.
- **Windows stack.** A window hidden under another can't be clicked; raise it from its Deskbar entry first (click the app, then the window name in the list that opens).
- **Passwords:** run the command and stop at the `[sudo] password` prompt; the user types it. `sudo` stays cached for about 15 minutes. The same goes for the OS login screen: leave it to the user, even when the password field is already filled.
- **Focus moves without warning.** After an idle spell the first click may only wake the screen, and restarting Deskbar takes focus from the Terminal. Click the window you mean to type into and screenshot before typing, or the text lands in another app.
- **Pop-up menus open with the checked item under the pointer**, so item positions change with the current choice. Screenshot each open menu before clicking an item.
- **VPN apps:** the exit address is easy to check from the guest without exposing anything: `curl -s https://api.ivpn.net/v4/geo-lookup | grep -oE '"(isIvpnServer|city)":[^,]*'` (or the provider's equivalent).
- **Put back what you changed** (settings, connections) and say so.

## Screenshots that must not show private data

`VBoxManage controlvm … screenshotpng` writes the full screen to disk. For apps that show an account ID, e-mail address or key, use `scripts/redactshot.py` instead: it grabs the screen into memory and saves only a redacted copy.

1. Read the app's source to find where the private text is drawn (a label at the bottom of the window, an item in a menu).
2. Before the window's position is known, use `--panel-bottom PX`: it blacks out the bottom PX pixels of each window panel, and blacks out the whole image when it finds none.
3. Once a redacted shot shows where the window sits, add `--fixed X0,Y0,X1,Y1` rectangles: over that area, and over a menu's private item before opening the menu. Be generous; a few lost pixels don't matter.
4. Keep only the shots you need; delete the rest.

- **Disk too small for the app?** Don't write your own partitioning tool: attach a bigger empty
  disk, partition it with DriveSetup and install with the OS's own Installer.
- **Haiku guests: use the Intel PRO/1000 NIC** (`--nictype1 82540EM`); the PCnet NIC stalls
  during large downloads.

## Audio and hangs

- **Host audio can hang power-off.** With VirtualBox 7.2.22 and PipeWire 1.6.10 (CachyOS, kernel 7.3), a VM whose audio driver is "default" (ALSA) gets stuck in `Stopping` on Power off or Reset; the log ends at `Console::powerDown(): A request to power off the VM has been issued`. Guest-initiated shutdown still works. Use `--audio-driver pulse`, or `--audio-driver null` when the guest only needs a device to exist. Kill a stuck VM by its process ID; a host reboot waits on it too.
- **Waiting for a guest:** the harness blocks chains of `sleep`. Poll screenshots in an `until` loop instead, e.g. until a pixel or the colour count says the desktop is up (`PIL.Image.open(shot).getcolors(1<<20)`).

## Hygiene

- Shut a guest down from inside (`sync; shutdown` on Haiku-family) before changing VM settings, so installed packages are kept.
- Never `pkill -f <word>` when the word is in your own command line: it kills the shell running it. Use `pkill -x <name>`.
- To remove a test VM: `VBoxManage controlvm <vm> poweroff; VBoxManage unregistervm <vm> --delete`. Ask the user first; they may want to keep it.
