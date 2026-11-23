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
    APP_PATH=${APP_PATH:-apps/$APP_NAME}      # the installed app, from /boot/system
    mkdir -p $E $S; HEAD=$(git rev-parse HEAD); P=$HOME/.claude/skills/beos-app-platforms/scripts
    HOSTIP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')   # how VMs reach host fixtures

Start the fixtures from the test plan. VMs reach them at `$HOSTIP` (127.0.0.1 and 10.0.2.2
don't work from VirtualBox NAT); Linux under Xvfb at 127.0.0.1. Fixture logs go to
`$E/<p>-<name>.log`, where `<p>` is `haiku`, `vos` or `linux`.

## Evidence file: `dist/V/evidence/<p>.txt`

    platform: haiku | vos | linux
    artifact: <file name>
    sha256: <sha256sum of the file in dist/V that you installed>
    commit: <git rev-parse HEAD the artifact was built from>
    os: <`uname -a` on Haiku; "VitruvianOS <vos package version> on <PRETTY_NAME> <uname -r>"; host distro + "X11 Xvfb/Openbox" on Linux>
    ci-run: <run id>                 (linux: appimage.yml run; vos: deb.yml run)
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

Before the first release of an app, and whenever its menus or windows
changed, go through the checklist at the end of hig.md on the Haiku build
and note the result in the evidence file.

## Driving the UI

1. `shot:<name>` (vm.sh or xtest.sh), then `ocr-find.sh $S/<name>.png <Label>` for X Y; `--text`
   shows everything OCR read. Small or grey labels may need a nearby word. What OCR misses:
   - **window titles**: Haiku's bold title on the yellow tab came out lowercase ("untitled"),
     and Openbox's white-on-blue title not at all. Match case-insensitively, and prefer one of
     the app's own labels (a menu name such as "Effects") for `launch`;
   - **small text on a large black root window** (Xvfb): OCR a crop of the app's window too;
   - **text along the top edge of a crop** (a menu bar in a window crop): OCR the whole screen
     too. Concatenating both readings into `<p>-screen.txt` is fine; both are the same shot;
   - **a short title or status line at screen scale**: crop just that strip and enlarge it 3×
     (`magick shot.png -crop 300x22+X+Y +repage -resize 300% title.png`) before OCR. Haiku's
     "resume-haiku" tab and Linux's "Saved …" status line read only that way;
   - **a word OCR splits** ("Pan" read as "P"): an empty `read X Y` then clicks at ","
     and nothing happens. Check the coordinates came back, or use known ones and say so.
2. Click: `m:click,X,Y` in a VM, `c:X,Y` under Xvfb. Menu items: hover first (virtualbox.md).
   A VM with a PS/2 pointer takes no absolute clicks: drive the app with `hey`
   (porting.md § 6, `hey-ui.sh`) and say so in the release notes' "Tested" section.
3. Type: click into the field, select all, then `t:<text>`. Select all is Haiku `k:38,1e,9e,b8`, V\OS `k:1d,1e,9e,9d`
   and Xvfb `k:ctrl+a`, but only if the app has no Select all menu item of its own: Ctrl/Alt+A
   then selects the whole document (EasyPaint), and the digits are appended to the field.
   Clear such a field with `k:End` and `k:BackSpace` instead.
4. **Know what the first launch shows.** An app that opens a "New Document" chooser when
   started without a document keeps it focused: Escape and Command+Q may not reach the app
   (Gobe Productive kept running), and the next launch with a document then opens it in that
   instance behind an untitled window that takes the typing. Close the chooser, check the
   process is gone (`ps`/`pgrep`), and only then launch with the test document; verify the
   window's title in every later shot, and check the saved file's content (`strings`), not
   only OCR of the window, for type-save-reopen.
5. Screenshot after every action and confirm it worked before the next one. Name shots
   `<p>-<step>.png`. Quote the OCR word *and* a log or file line in the evidence: a screenshot
   of the wrong window has passed for success before.
6. Window positions: `eval $(xdotool getwindowgeometry --shell $W | sed 's/^/G_/')`. Without
   the prefix it sets `X`, `Y`, `WIDTH`, `HEIGHT`, `SCREEN` and `WINDOW`, and `X` is the
   evidence file in the `chk` helper above.
7. Every part of a PASS condition is a check. "The red rectangle and the text" needs the
   text in OCR *and* a red pixel on the rectangle's edge (PIL `getpixel`; sample a few pixels
   around the expected line, which may be one off).

## Test VMs

Every release is tested on five artifacts, four of them in VMs, all in QEMU (no VirtualBox). The
VMs are shared by every app: install, test, remove. Each runs an OS installed onto its own
20 GB+ disk image, never a small copy of the install image. Keep this machine's details (SSH
key, ports, which VMs exist) in your local notes or memory, not in this skill.

| Artifact | VM | How it runs | Firmware, screen | Command key | Reference |
|---|---|---|---|---|---|
| `.hpkg` x86_64 | `haiku-b6-test`: Haiku R1/beta6 | `qemu-vm.sh` (KVM), SSH | BIOS, 1024×768 | **Alt** | below |
| `.hpkg` arm64 | Renku OS arm64 nightly | `haiku-arm64-vm.sh` (emulated), desktop only | UEFI, 1024×768 | **Alt** | haiku-arm64.md § Test |
| `.deb` amd64 | `vos-test`: VitruvianOS | QEMU/KVM + OVMF, SSH | UEFI, 1280×800 | **Ctrl** | vitruvianos.md § Test VMs |
| `.deb` arm64 | `vos-arm64`: VitruvianOS | QEMU virt (emulated) + edk2 | UEFI | **Ctrl** | vitruvianos.md § Test VMs |
| AppImage x86_64 / aarch64 | none: Xvfb here; CI on arm64 | | | **Ctrl** | below |

**Create a Haiku VM:** boot the official anyboot image as installer media with an empty raw
disk beside it, install onto that disk with Installer, write the image's MBR boot code to it,
then set up SSH (renku.md § SSH) and `pkgman install -y gcc make haiku_devel`. SSH aliases in
`~/.ssh/config`: `HostName 127.0.0.1`, the port, the user, `IdentityFile <key>`,
`IdentitiesOnly yes`, `StrictHostKeyChecking accept-new`,
`UserKnownHostsFile ~/.ssh/known_hosts_testvms`.

**No test VM for a platform on this machine?** Ask before using any other VM, even for one
release, and note it as a `DECISION`. **Only drive the test VMs.** Never start, stop, modify or
delete any other VM; the one thing you may do with another is copy *from* its disk while it's
off.

**Start them detached** (`setsid nohup … &`): a QEMU started from a background task dies when
that task is stopped, leaving the disk dirty. Judge a boot by screenshots (OCR for "Tracker" or
"Deskbar"), not by a line in the serial log, and watch long waits with a monitor that reports
stalls. A black screenshot is usually the screen blanker: move the pointer first.

**Shut down** from inside (installed packages are kept): `ssh haiku-b6-test 'sync; shutdown'`,
`ssh vos-test 'sudo poweroff'`, `haiku-arm64-vm.sh shutdown`; pull the plug only after 2 minutes.

## Haiku R1/beta6 (`haiku-b6-test`)

    F=${APP_CMD}-${V}-${REVISION}-x86_64.hpkg
    ssh haiku-b6-test 'uname -a'                                       # -> os:
    ssh haiku-b6-test "pkgman uninstall -y $APP_CMD" 2>&1 | tail -1    # "not installed" is fine
    # One name per uninstall: given several, pkgman refuses them all if any isn't installed
    # (an old package name in HPKG_REPLACES, say), and the old package stays.
    scp $D/$F haiku-b6-test:/tmp/ && ssh haiku-b6-test "pkgman install -y /tmp/$F" 2>&1 | tail -3
    ssh haiku-b6-test "ls /boot/system/packages | grep '^$APP_CMD-'"   # install: must show $F
    ssh haiku-b6-test "sha256sum /boot/system/packages/$F"             # install: must equal $D/$F's
    # The name alone isn't proof: installing a rebuilt package of the same version over one
    # still installed changes nothing, and the test then runs the old build.
    ssh haiku-b6-test "catattr BEOS:APP_SIG /boot/system/$APP_PATH"   # attrs
    # fresh state: delete what the test plan names
    ssh haiku-b6-test "(/boot/system/$APP_PATH > /tmp/app.log 2>&1 &)"; sleep 5
    DIR=~/VMs/haiku-b6-test sh $P/qemu-vm.sh shot $S/haiku-launch
    … feature steps …
    DIR=~/VMs/haiku-b6-test sh $P/qemu-vm.sh key alt-q                 # click the window first
    ssh haiku-b6-test "ps | grep -v grep | grep -c '/$APP_PATH'"    # quit: 0 (count your own grep out)
    scp haiku-b6-test:/tmp/app.log $E/haiku-app.log

A GUI app started over SSH appears on the Haiku desktop. **Wake the screen first:** after a
few idle minutes Haiku's screen blanker turns the screen black, and the first key or click
only wakes it (screenshots come out black, the first typed letter is lost). Move the pointer
(`qemu-vm.sh move`) before launching, and again before typing after any long step. If `pkgman`
asks for confirmation even with `-y`, a dependency is missing: add it to `HPKG_REQUIRES_EXTRA`
and the test plan.

## Renku OS arm64

Run the same plan on the Renku arm64 nightly (haiku-arm64.md § Test): install, attrs, launch,
the feature checks (or `CHECK <name> N/A <why>` for one that can't run there), quit, the app's
log. Evidence: `$E/haiku-arm64.txt`.

## VitruvianOS (`vos-test`, amd64)

    F=${APP_CMD}_${V}-${REVISION}_amd64.deb
    echo "VitruvianOS $(ssh vos-test "dpkg-query -W -f '\${Version}' vos") on $(ssh vos-test '. /etc/os-release; echo "$PRETTY_NAME $(uname -r)"')"  # -> os:
    ssh vos-test "sudo apt-get purge -y $APP_CMD" 2>&1 | tail -1
    scp $D/$F vos-test:/tmp/ && ssh vos-test "sudo apt-get install -y /tmp/$F" 2>&1 | tail -3
    ssh vos-test "dpkg-query -W $APP_CMD; test -s /system/apps/$APP_NAME && echo nonempty"   # install
    ssh vos-test "getfattr -d -m user.beos /system/apps/$APP_NAME" | grep APP_SIG          # attrs
    ssh vos-test "sha256sum /system/apps/$APP_NAME"; dpkg-deb --fsys-tarfile $D/$F | tar -xO ./system/apps/$APP_NAME | sha256sum   # must match

Launch over SSH (`ssh vos-test "(/system/apps/$APP_NAME > /tmp/app.log 2>&1 &)"`) and take a
screenshot; if no window appears, start it from the desktop Terminal instead. Quit with Ctrl+Q,
check `pgrep -x $APP_NAME || echo gone`, copy `/tmp/app.log` to `$E/vos-app.log`.

## VitruvianOS arm64 (`vos-arm64`)

The arm64 `.deb` runs on V\OS's arm64 UEFI image in QEMU's emulated virt machine
(vitruvianos.md § Test VMs). Run the same plan: install, attrs, launch, the feature checks (or
`CHECK <name> N/A <why>`), quit, the app's log. `check-artifact.sh deb` checks it statically
too. Evidence: `$E/vos-arm64.txt`, with the CI run in `ci-run:`.

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

- AppImageLauncher on the host intercepts AppImages with an "integrate" dialog: `xtest.sh`
  sets `APPIMAGELAUNCHER_DISABLE=1`; set it yourself when you start one another way. Its
  bypass prints one `[appimagelauncher-binfmt-bypass/interpreter]` line into the app log;
  it has no error words, so leave the log as it is.
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
check. A downloaded AppImage isn't executable: `chmod +x` it, or `xtest.sh start` gives a
black screen and an empty log. Write the results to `$E/<p>-release.txt` in the same format, `artifact: <the URL>`.
