# Task: build a Haiku app inside a VirtualBox VM and test it with the VirtualBox SDK

You are working on a Linux host. You will build a C++ app written against the Haiku (BeOS) API inside a Haiku VM running in VirtualBox, then test it by controlling the VM from the host: typing, clicking and taking screenshots. Follow the steps in order. After every step, check the "Expect" line. If the result is different, try the "If it fails" advice once. If it still fails, **stop and report** what you saw. Don't improvise around problems.

## 0. Fill these in before starting

```
APP=<app name as it appears in window titles and `ps`, e.g. Folio>
REPO=<absolute path of the app's git checkout on the host>
VM=<VM name to create or use, e.g. myapp-haiku>
ISO=<absolute path of a Haiku or Renku OS *anyboot* .iso>
SCRATCH=<a scratch folder on the host for screenshots, e.g. /tmp/vmtest>
```

Renku OS (a Haiku fork) works the same way. Use its nightly ISO instead.

## Rules (read twice)

1. Only control the VM named `$VM`. Run `VBoxManage list vms` first. **Never** start, stop, change or delete any other VM.
2. **Take a screenshot before every click** and read it. Screen positions in this prompt are typical, not guaranteed.
3. Ask the user before step 5 (SSH setup). It changes the VM permanently.
4. Never use `pkill -f <word>`: it can kill your own shell. Use `pkill -x <exact name>`.
5. Don't try to log in on text consoles, and don't read password files.
6. Don't file bugs, patches or posts with the Haiku project. If you find a platform bug, just describe it in your report.
7. Don't delete the VM or its disk at the end.

## Helpers (create these on the host first)

Save this as `$SCRATCH/vm.sh`. It sends keys and text and takes screenshots:

```sh
#!/bin/sh
# usage: VM=<name> sh vm.sh STEP...   steps: k:<hex,…>  t:<text>  w:<secs>  shot:<name>
for step in "$@"; do
  case "$step" in
  k:*) VBoxManage controlvm "$VM" keyboardputscancode $(echo "${step#k:}" | tr ',' ' ') ;;
  t:*) VBoxManage controlvm "$VM" keyboardputstring "${step#t:}" ;;
  w:*) sleep "${step#w:}" ;;
  shot:*) VBoxManage controlvm "$VM" screenshotpng "$SCRATCH/${step#shot:}.png"; echo "$SCRATCH/${step#shot:}.png" ;;
  esac
done
```

Save this as `$SCRATCH/mouse.py`. It sends mouse input through the VirtualBox SDK:

```python
# usage: VM=<name> python3 mouse.py ACTION X Y [X2 Y2]
# ACTION: move click rclick dclick altclick drag. X,Y = screenshot pixels.
import os, sys, time
from vboxapi import VirtualBoxManager
act, x, y = sys.argv[1], int(sys.argv[2]) + 1, int(sys.argv[3]) + 1
mgr = VirtualBoxManager(None, None); vb = mgr.getVirtualBox()
s = mgr.getSessionObject(vb)
vb.findMachine(os.environ["VM"]).lockMachine(s, mgr.constants.LockType_Shared)
m, kbd = s.console.mouse, s.console.keyboard
def at(px, py, b=0):
    m.putMouseEventAbsolute(px, py, 0, 0, b); time.sleep(0.08)
def click(px, py, b=1):
    at(px, py); at(px, py, b); at(px, py)   # hold the button briefly, like a real click
try:
    if act == "move": at(x, y)
    elif act == "click": click(x, y)
    elif act == "rclick": click(x, y, 2)
    elif act == "dclick": click(x, y); click(x, y)
    elif act == "altclick":
        kbd.putScancodes([0x38]); click(x, y); kbd.putScancodes([0xB8])
    elif act == "drag":
        x2, y2 = int(sys.argv[4]) + 1, int(sys.argv[5]) + 1
        at(x, y); at(x, y, 1)
        for i in range(1, 11): at(x + (x2 - x) * i // 10, y + (y2 - y) * i // 10, 1)
        at(x2, y2)
finally:
    s.unlockMachine(); os._exit(0)
```

Keyboard scancodes for `k:`: a press is the code, and the release is the code + 0x80.

- Enter `1c,9c`; Backspace `0e,8e`; Escape `01,81`
- **Alt is Haiku's command key**: Alt+Q = `38,10,90,b8`, Alt+R = `38,13,93,b8`, Alt+W = `38,11,91,b8`
- Other letter codes: A 1e, S 1f, D 20, F 21, N 31, O 18, I 17, T 14

## 1. Preflight

```sh
mkdir -p "$SCRATCH"
VBoxManage --version
python3 -c "import vboxapi; print('vboxapi ok')"
VBoxManage list vms
```

- **Expect:** a 7.x version, `vboxapi ok`, and the VM list.
- **If `vboxapi` is missing:** stop and ask the user to install the VirtualBox SDK. On Arch it's `sudo pacman -S virtualbox-sdk`, and it must match the VirtualBox version.

## 2. Create the VM (skip if `$VM` already exists and has the build tools)

```sh
D="$HOME/VirtualBox VMs/$VM"; mkdir -p "$D"
VBoxManage convertfromraw "$ISO" "$D/disk.vdi" --format VDI
VBoxManage createvm --name "$VM" --ostype Other_64 --register
VBoxManage modifyvm "$VM" --memory 4096 --cpus 4 --graphicscontroller vboxsvga --vram 64 \
  --nic1 nat --audio-enabled off --mouse usbtablet --usbohci on --ioapic on
VBoxManage storagectl "$VM" --name SATA --add sata --portcount 1
VBoxManage storageattach "$VM" --storagectl SATA --port 0 --device 0 --type hdd --medium "$D/disk.vdi"
VBoxManage modifyvm "$VM" --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
VBoxManage startvm "$VM" --type headless
```

The anyboot ISO converted to VDI boots as a **writable hard disk**, so whatever you install stays. `--mouse usbtablet` is needed for exact clicks. The port forward lets the host reach the guest's SSH later.

**Expect:** "VM has been successfully started".

## 3. First boot

Wait about 45 s, then take a screenshot: `VM=$VM sh $SCRATCH/vm.sh shot:boot`, and read the PNG.

- **Expect:** a "Welcome" window with **Install** and **Try it out** / **Try Haiku** buttons, on a 1024×768 screen.
- Click the "Try…" button (about x=775, y=566): `VM=$VM python3 $SCRATCH/mouse.py click 775 566`
- Wait 15 s and take a screenshot. **Expect:** the desktop with icons top-left and the **Deskbar** top-right.
- **If the screenshot is black:** the screen blanker is on. Run `mouse.py move 500 500` and take another.
- On later boots of the same VM the welcome window may not appear. That's fine.

## 4. Open a Terminal in the guest

1. Click the Deskbar's logo (about 955,12).
2. Screenshot. Hover "Applications" (`mouse.py move 785 226`).
3. Screenshot. The submenu opens to the **left**. Move left into it first (`move 640 226`), then down to **Terminal** (read its y from the screenshot, usually about 698–707), and click it.
4. **Expect:** a Terminal window with a `~>` prompt.

Type a command with `t:` followed by Enter. Check that the toolchain is there:

```
VM=$VM sh $SCRATCH/vm.sh "t:which gcc make; uname -a; df -h /boot | tail -1" k:1c,9c w:2 shot:t1
```

## 5. One-time SSH setup (ask the user first)

Without SSH, the only way to get files in is typing them, which is far too slow. Ask: "May I enable key-only SSH in the VM? It stays enabled across reboots." Continue only with a yes.

1. On the host, create a key if there isn't one: `ssh-keygen -t ed25519 -N '' -f ~/.ssh/vm_ed25519`
2. Find the host's LAN IP: `ip route get 1.1.1.1 | grep -oP 'src \K\S+'`. VirtualBox NAT blocks the guest from reaching the host's `127.0.0.1`, so use the LAN IP.
3. In an empty folder on the host, write `setup.sh`, replacing `PUBKEY` with the contents of `~/.ssh/vm_ed25519.pub`:

   ```sh
   #!/bin/sh
   set -e
   PUB='PUBKEY'
   mkdir -p "$HOME/config/settings/ssh"            # Haiku's sshd reads keys from here
   echo "$PUB" >> "$HOME/config/settings/ssh/authorized_keys"
   chmod 600 "$HOME/config/settings/ssh/authorized_keys"
   C=/boot/system/settings/ssh/sshd_config; mkdir -p "${C%/*}"; touch "$C"
   sed -i '/^PermitRootLogin/d; /^PasswordAuthentication/d' "$C"
   printf 'PermitRootLogin prohibit-password\nPasswordAuthentication no\n' >> "$C"   # the Haiku user is uid 0
   ssh-keygen -A
   for p in $(ps | awk '/[s]shd/ {print $(NF-3)}'); do kill $p || :; done   # team id is 4th from the end
   sleep 1; /bin/sshd                                # must be an absolute path
   echo "sshd setup done"
   ```

4. Serve that folder in the background: `python3 -m http.server 8731 --bind <LAN-IP> --directory <folder>`
5. In the guest Terminal: `t:curl http://<LAN-IP>:8731/setup.sh | sh` then `k:1c,9c`. **Expect** `sshd setup done` in a screenshot.
6. Stop the HTTP server. Add to `~/.ssh/config`:

   ```
   Host haiku-vm
       HostName 127.0.0.1
       Port 2222
       User user
       IdentityFile ~/.ssh/vm_ed25519
       IdentitiesOnly yes
       StrictHostKeyChecking accept-new
   ```

7. Test: `ssh haiku-vm uname -a`. **Expect:** a line starting with `Haiku`.
   **If it asks for a password:** the old sshd is still running. Type `kill <team id from ps>` then `/bin/sshd` in the guest Terminal and retry.

From now on, run guest commands with `ssh haiku-vm '…'`.

## 6. Install the build tools (once)

```sh
ssh haiku-vm 'pkgman install -y gcc make haiku_devel 2>&1 | tail -2; gcc --version | head -1; make --version | head -1'
```

- **Expect:** gcc and make version lines.
- **If headers are missing later** ("stdlib.h: No such file"): a system update was half-applied. Reboot the VM by typing `t:shutdown -r` in the Terminal, wait for it, and retry.

## 7. Copy the source and build

```sh
cd "$REPO"
git archive HEAD | ssh haiku-vm 'rm -rf ~/build && mkdir ~/build && tar -x -C ~/build 2>/dev/null; cd ~/build && find . -exec touch {} +'
ssh haiku-vm 'cd ~/build && (make test 2>&1 | tail -3); make 2>&1 | grep -iE "warning|error" ; ls -l'
```

`git archive` sends exactly the committed tree. The `touch` avoids "clock skew" warnings, because the VM clock is often hours off.

- **Expect:** tests pass (if the project has `make test`), no errors, and a binary in the listing. Record any warnings.
- If the project has `make hpkg`, also run `ssh haiku-vm 'cd ~/build && make hpkg 2>&1 | tail -3'`, then `ssh haiku-vm 'cd ~/build && package list *.hpkg'`. **Expect** `apps/<App>` and the `requires:` line.

## 8. Install or launch

- **Package:**
  `ssh haiku-vm 'cd ~/build && pkgman install -y ./*.hpkg && listattr /boot/system/apps/'"$APP"' | grep BEOS'`
  **Expect** 5 BEOS attributes, including `BEOS:APP_SIG`.
- **No package:** run it from the build folder.
- **Launch with a log** (GUI apps started over SSH appear on the VM's screen):
  `ssh haiku-vm 'cd ~/build && (./'"$APP"' > /tmp/app.log 2>&1 &)'`, or with `open /boot/system/apps/$APP` when installed.
- Wait 4 s and take a screenshot. **Expect:** the app's window, fully on screen (1024×768).

## 9. Test through the VirtualBox SDK

Test what the app actually does: read its README for its main features. For each feature:

1. Take a screenshot and find the control.
2. Act: `mouse.py click X Y` / `rclick` / `altclick`, `vm.sh "t:text"`, or `k:` for shortcuts (Alt is the command key).
3. Wait 1–2 s and take a screenshot. Compare it with what should have happened.
4. **Check the result on disk over SSH**, not just on screen: `cat`, `ls`, `listattr <file>`, `catattr <attr> <file>`.

Always include these platform checks when the app uses them:

- **Window fit:** the window is fully visible at 1024×768.
- **Menus:** click each top-level menu and take a screenshot; Escape `k:01,81` closes it.
- **File panel** (Open / Attach / Save): it opens. Type the start of a file name to select it, then press Enter. The file is used.
- **Files changed from outside:** with the app running, rename a file it watches over SSH (`mv old new`). Check whether the app noticed (screenshot plus its saved files).
- **Trash** (if it has "Move to Trash"):
  `ssh haiku-vm 'ls $(finddir B_TRASH_DIRECTORY); catattr _trk/original_path "$(finddir B_TRASH_DIRECTORY)/<file>"'`
- **Attributes and queries** (if it writes attributes): `lsindex`, then `query '<ATTR>=*value*'`.
- **Errors:** `ssh haiku-vm cat /tmp/app.log` should be empty or harmless.

To quit the app: Alt+Q (`k:38,10,90,b8`), or `ssh haiku-vm 'hey <App> quit'`. `hey` may print "Error when sending message"; that's harmless.

## 10. Bring results back

```sh
scp 'haiku-vm:build/*.hpkg' "$REPO"/    # if a package was built
```

Leave the VM running unless the user says otherwise. To shut it down cleanly: `ssh haiku-vm 'sync; shutdown'`.

## 11. Report (use exactly this structure)

```
Haiku/Renku version: <uname -a>
Build: <passed/failed>; tests <N passed / N failed>; warnings: <list or none>
Package: <file name, size> or "none"; install: <ok/failed + output>
Feature tests:
- <feature>: <pass/fail> — <what you did, what happened, file evidence>
Problems found: <each with steps to reproduce, screenshot path, and whether it's the app or the OS>
Not tested: <anything you skipped, and why>
```

Mark a test as passed only if you saw it work in a screenshot **and** confirmed it on disk or in the log. Don't guess.
