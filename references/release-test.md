# Testing release artifacts on their platforms

Every platform gets the same standard checks, plus the app's own feature checks from
`release/test-plan.md` (onboard.md §5):

| Check | PASS means (all from output you saw) |
|---|---|
| `install` | the package manager installed exactly this file, no errors |
| `attrs` | the installed binary has `BEOS:APP_SIG` = `$APP_SIG` (Linux: the signature string is in the binary) |
| `launch` | a screenshot read with OCR shows the app's window (title or a known label) |
| *feature checks* | the PASS condition in the test plan, shown by raw evidence |
| `log-clean` | the app's stdout/stderr log has no error, assert, crash or exception lines |
| `quit` | after the app's own Quit command, its process is gone within 10 s |
| `wayland` (Linux) | the CI smoke test's screenshot shows the window, its log is clean |
| `x11`, `wayland` (Linux aarch64) | the arm64 CI job's smoke screenshots show the window, both logs are clean |

## Setup, every time

    . ./haiku-app.env; V=$VERSION; D=dist/$V; E=$D/evidence; S=$D/shots
    mkdir -p $E $S; HEAD=$(git rev-parse HEAD); P=$HOME/.claude/skills/beos-app-platforms/scripts
    HOSTIP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')   # how VMs reach host fixtures

Start the fixtures from the test plan. VMs reach them at `$HOSTIP` (127.0.0.1 and 10.0.2.2
don't work from VirtualBox NAT); Linux under Xvfb at 127.0.0.1. Fixture logs go to
`$E/<p>-<name>.log`, where `<p>` is `haiku` or `linux`.

## Evidence file: `dist/V/evidence/<p>.txt`

    platform: haiku | linux
    artifact: <file name>
    sha256: <sha256sum of the file in dist/V that you installed>
    commit: <git rev-parse HEAD the artifact was built from>
    os: <`uname -a` on Haiku; host distro + "X11 Xvfb/Openbox" on Linux>
    ci-run: <run id>                 (linux: the appimage.yml run)
    CHECK install PASS <command> -> <the line that proves it>
    CHECK <name> PASS|FAIL <evidence file or command>: "<matching line>"
    RESULT: PASS            (only if every CHECK is PASS; otherwise RESULT: FAIL)

Also save, because the gate reads them directly: `$E/<p>-app.log` (the app's whole log),
`$E/<p>-screen.txt` (`ocr-find.sh --text` of the shot showing the feature result), the files the
`EVIDENCE_n` rules name, and fixture logs.

**Write a PASS line only after testing its condition.** Script the run with a helper, so a dead
display or a failed command can't produce PASS lines:

    chk() { n=$1 t=$2; shift 2
    	if "$@"; then echo "CHECK $n PASS $t" >> $X; else echo "CHECK $n FAIL $t" >> $X; FAILS=$((FAILS+1)); fi; }
    chk rename-links "$p-links.txt: \"$(tr '\n' ' ' < $E/$p-links.txt)\"" grep -q "Renamed $p" $E/$p-links.txt

A failing check stays FAIL with the reason. Find the cause and fix the app; don't retry until it
passes by luck. Run scripts with `bash`: zsh aborts a whole command on an unmatched glob.

## Driving the UI

1. `shot:<name>` (vm.sh or xtest.sh), then `ocr-find.sh $S/<name>.png <Label>` for X Y; `--text`
   shows everything OCR read. Small or grey labels may need a nearby word.
2. Click: `m:click,X,Y` in a VM, `c:X,Y` under Xvfb. Menu items: hover first (virtualbox.md).
3. Type: click into the field, select all (Haiku `k:38,1e,9e,b8`; Xvfb `k:ctrl+a`), then `t:<text>`.
4. Screenshot after every action and confirm it worked before the next one. Name shots
   `<p>-<step>.png`. Quote the OCR word *and* a log or file line in the evidence: a screenshot
   of the wrong window has passed for success before.

## Test VM

One shared VM serves every app: install, test, remove. Keep this machine's details (SSH key,
which known-good VMs exist to clone from) in your local notes or memory, not in this skill.

| VM | SSH alias | Host port | Firmware, screen | Guest user | Command key |
|---|---|---|---|---|---|
| `haiku-b6-test` | `haiku-b6-test` | 127.0.0.1:2224 | BIOS, 1024×768 | `user` (uid 0) | **Alt** |

**Only drive this one.** Never start, stop, modify or delete any other VM; the one thing you
may do with another VM is clone *from* it while it's powered off.

**Create (once per machine):** `VBoxManage list vms`. Fastest is cloning a known-good VM that
already has the toolchain and SSH (must be `poweroff`), then changing its port **before the
first boot**, since source VMs usually forward 2222:

    VBoxManage clonevm <source> --name haiku-b6-test --register --mode machine
    VBoxManage modifyvm haiku-b6-test --natpf1 delete ssh
    VBoxManage modifyvm haiku-b6-test --natpf1 "ssh,tcp,127.0.0.1,2224,,22"

Without one: `sh $P/make-vm.sh haiku-b6-test ~/Downloads/haiku-r1beta6-x86_64-anyboot.iso`, add
the port forward (powered off), set up SSH (renku.md § SSH), and
`ssh haiku-b6-test pkgman install -y gcc make haiku_devel`. SSH aliases in `~/.ssh/config`:
`HostName 127.0.0.1`, the port, the user, `IdentityFile <key>`, `IdentitiesOnly yes`,
`StrictHostKeyChecking accept-new`, `UserKnownHostsFile ~/.ssh/known_hosts_testvms`.

**Boot:** `VBoxManage startvm <vm> --type headless`, then
`for i in $(seq 60); do ssh -o ConnectTimeout=5 -o BatchMode=yes <vm> true && break; sleep 5; done`.
Haiku starts sshd by itself (`uname -a` shows `hrev59866`).

**Shut down** (installed packages are kept): `ssh haiku-b6-test 'sync; shutdown'`; only after
2 minutes, `VBoxManage controlvm <vm> poweroff`.

## Haiku R1/beta6 (`haiku-b6-test`)

    F=${APP_CMD}-${V}-${REVISION}-x86_64.hpkg
    ssh haiku-b6-test 'uname -a'                                       # -> os:
    ssh haiku-b6-test "pkgman uninstall -y $APP_CMD" 2>&1 | tail -1    # "not installed" is fine
    scp $D/$F haiku-b6-test:/tmp/ && ssh haiku-b6-test "pkgman install -y /tmp/$F" 2>&1 | tail -3
    ssh haiku-b6-test "ls /boot/system/packages | grep '^$APP_CMD-'"   # install: must show $F
    ssh haiku-b6-test "catattr BEOS:APP_SIG /boot/system/apps/$APP_NAME"   # attrs
    # fresh state: delete what the test plan names
    ssh haiku-b6-test "(/boot/system/apps/$APP_NAME > /tmp/app.log 2>&1 &)"; sleep 5
    VM=haiku-b6-test SCRATCH=$S sh $P/vm.sh shot:haiku-launch
    … feature steps …
    VM=haiku-b6-test sh $P/vm.sh k:38,10,90,b8                        # Alt+Q (click the window first)
    ssh haiku-b6-test "ps | grep -v grep | grep -c '/apps/$APP_NAME'" # quit: 0 (count your own grep out)
    scp haiku-b6-test:/tmp/app.log $E/haiku-app.log

A GUI app started over SSH appears on the Haiku desktop. If `pkgman` asks for confirmation
even with `-y`, a dependency is missing: add it to `HPKG_REQUIRES_EXTRA` and the test plan.

## Linux (the CI AppImage, under Xvfb)

    F=${APP_NAME}-${V}-x86_64.AppImage; chmod +x $D/$F
    [ -e /tmp/.X11-unix/X99 ] || (Xvfb :99 -screen 0 1280x800x24 -nolisten tcp > /dev/null 2>&1 &)
    pgrep -x openbox > /dev/null || (DISPLAY=:99 openbox > /dev/null 2>&1 &)
    DISPLAY=:99 xdotool getmouselocation || echo "display :99 is dead"     # check before testing
    rm -rf $S/xhome; export APP=$PWD/$D/$F APP_NAME HOME_DIR=$PWD/$S/xhome SCRATCH=$PWD/$S
    sh $P/xtest.sh start shot:linux-launch          # app log: $S/app.log
    … feature steps (c:X,Y  k:ctrl+a  t:text  shot:name) …
    sh $P/xtest.sh k:ctrl+q w:3; pgrep -x "$APP_NAME" || echo gone
    cp $S/app.log $E/linux-app.log

- `install`: `check-artifact.sh appimage` passed and the file is the CI artifact (`ci-run:`).
  `attrs`: `strings -a` of the extracted binary shows `$APP_SIG`.
- `wayland`: look at `smoke-x86_64/wayland-smoke/wayland-screenshot.png` from the same CI run,
  and cite it: `CHECK wayland PASS …/wayland-screenshot.png: <what it shows>; app.log clean`.
  Save its log as `$E/linux-wayland.log`.
- No text at all in OCR means fonts are missing from the AppImage: a real bug
  (cosmoe-linux.md § Package an AppImage).

## Linux aarch64 (the CI AppImage, on GitHub's arm64 runner)

There's no arm64 desktop here, so the `aarch64` job of `appimage.yml` is the test machine: it
started the AppImage under X11 and Wayland on real arm64 hardware and uploaded `smoke-aarch64`.
Look at both screenshots, then write `$E/linux-arm64.txt`:

    platform: linux-arm64
    artifact: <App>-<V>-aarch64.AppImage
    sha256: … / commit: … / ci-run: <the appimage.yml run>
    CHECK install PASS check-artifact.sh appimage <file> -> CHECKS PASSED n (aarch64 binary)
    CHECK x11 PASS smoke-aarch64/x11-smoke/x11-screenshot.png: <what it shows>; app.log <n> lines
    CHECK wayland PASS smoke-aarch64/wayland-smoke/wayland-screenshot.png: <what it shows>; app.log <n> lines
    RESULT: PASS

and copy the two app logs to `$E/linux-arm64-x11.log` and `$E/linux-arm64-wayland.log`. The
app's feature checks were not run on arm64: say so in the release notes.

## After publishing

In each VM, `curl -fsSLO https://github.com/$GITHUB_REPO/releases/download/v$V/<file>`, check its
`sha256sum` against `SHA256SUMS`, then repeat `install`, `attrs`, `launch` and one feature
check. Write the results to `$E/<p>-release.txt` in the same format, `artifact: <the URL>`.
