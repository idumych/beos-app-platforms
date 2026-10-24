# Renku OS (and Haiku-family guests)

Renku OS (github.com/RenkuOS/Source) is a fork of Haiku that started in September 2026. For packaging it's still Haiku:

- **Package name and version.** The system package is still called `haiku`, with `HAIKU_VERSION = r1~beta6` (`build/jam/BuildSetup`). A package that `requires { haiku >= r1~beta6 }` installs on both Haiku R1/beta6 and Renku. A binary built on Haiku beta6 ran unchanged on Renku nightly build00055 (hrev60072+253).
- **Nightlies:** `gh release view nightly -R RenkuOS/Source` (x86_64 and x86_gcc2h ISOs, each with a `.sha256`). Download into `~/Downloads` and check with `sha256sum -c`. Some nights only the x86_gcc2h ISO is attached, so there may be no x86_64 image until a later build.
- **Policy:** `AGENTS.md` in RenkuOS/Source, plus `RenkuOS/PlanAndGovernance` (CONTRIBUTING, REVIEW, DECISIONS). Machine-assisted work is allowed. Pull requests need a short human-style summary, a "How this was tested" section and a DCO `Signed-off-by`. Issues go to RenkuOS/Source. Renku has its own package repository ("Spritz Depot"); see its open issues for the submission process.

## arm64

Blocked as of Oct 2026; check at every release, and build an arm64 `.hpkg` as soon as one of these turns up:

    curl -s -o /dev/null -w '%{http_code}\n' https://eu.hpkg.haiku-os.org/haiku/r1beta6/arm64/current/   # 404 = no arm64 R1/beta6 repo
    gh release view nightly -R RenkuOS/Source --json assets -q '.assets[].name' | grep -i arm             # a Renku arm64 ISO?
    curl -fsSL https://raw.githubusercontent.com/cross-platform-actions/action/master/readme.md | grep -A8 '(`haiku`)'   # Haiku arm64 in CI?

Haiku's arm64 nightlies (`download.haiku-os.org/nightly-images/arm64/`) are experimental SD-card images with no package repository, and VirtualBox on an x86 host can't run arm64 guests; a QEMU `aarch64` VM would be the test machine. The `.hpkg` itself needs no changes beyond `getarch` reporting `arm64`.

## Make a test VM

```sh
sh scripts/make-vm.sh <name> ~/Downloads/RenkuOS-x86_64-<date>-build<NNN>.iso
```

The ISO is an *anyboot* hybrid image, so converted to VDI it boots as a writable hard disk with BIOS firmware. The screen is 1024×768. The same applies to Haiku's own anyboot images.

- **First screen:** "Welcome!", with **Try it out** at about (778,566). It leads to the desktop, logged in, with the Deskbar top-right.
- **Terminal:** click the Deskbar logo at (955,12), hover Applications (785,226), move left (640,226), go down to Terminal at about (625,707), then click. Screenshot first; positions shift as the menu changes.
- **Free space:** about 300 MB on the boot disk. Packages stay compressed, so `pkgman install gcc make` fits. `haiku_devel` was already installed on the Haiku beta6 image.
- **Clock:** the VM clock runs in local time while the host assumes UTC, so tar and make warn "time stamp in the future". Fix with `find . -exec touch {} +`, or rely on `make clean`.
- **Screen blanker:** if a screenshot is black, move the mouse (`m:move,…`) and take it again.

### When it hangs on the boot splash

Haiku R1/beta6 (hrev59866+79) hung with all splash icons lit on most boots in VirtualBox 7.2.22, whatever the disk controller, graphics, CPU count, audio or second disk. An older nightly (hrev59741) booted every time in the same VM. To see why:

1. **Serial log:** with the VM off, `VBoxManage modifyvm <vm> --uart1 0x3F8 4 --uartmode1 file <path>`. The image doesn't log to serial by default: press Space repeatedly right after starting (`k:39,b9`) to get the boot menu, then **Select debug options → Enable serial debug output** → Return → **Continue booting**. The option lasts one boot.
2. **Kernel debugger:** Alt+SysRq+D = `k:38,54,20,a0,d4,b8`. Type commands with `t:` and Enter; output goes to the serial log. Useful ones: `teams`, `threads <team>`, `bt <thread>`, `syslog | grep <word>`, `syslog | tail 30`.
3. In that hang, `teams` showed no `app_server`, and `media_server` with a team ID in the tens of thousands (restarting in a loop inside `runtime_loader`).

## Get files in and out

- **Published files:** `curl -fsSLO <release URL>` inside the guest (curl ships; wget may not).
- **Everything else:** set up SSH once (below), then use `ssh`/`scp`/`tar | ssh`. Without SSH, small files can be typed in as base64 with `vm.sh t:`, but that's slow: about 1 KB per 30 s into a Haiku Terminal.

## SSH into a Haiku-family guest (once per VM)

Ask the user before doing this: it installs a key and keeps sshd enabled at boot, which auto mode flags as persistence. Steps:

1. Shut the guest down from inside (`sync; shutdown`), add a port forward with `VBoxManage modifyvm <vm> --natpf1 "ssh,tcp,127.0.0.1,2222,,22"`, then start it again.
2. Key: `ssh-keygen -t ed25519 -N '' -f ~/.ssh/<name>_ed25519`. Add a host alias in `~/.ssh/config`: `HostName 127.0.0.1`, `Port 2222`, `User user`, `IdentityFile …`, `IdentitiesOnly yes`, `StrictHostKeyChecking accept-new`, and a separate `UserKnownHostsFile`.
3. Run `sh scripts/serve-ssh-setup.sh ~/.ssh/<name>_ed25519.pub` in the background. It serves on the host's **LAN IP**, because VirtualBox 7 NAT blocks guest-to-host localhost.
4. Type the printed `curl … | sh` line into the guest Terminal, then stop the server.

What makes Haiku's sshd different (the script handles all of it):

- Keys are read from **`~/config/settings/ssh/authorized_keys`**, not `~/.ssh/`.
- The user is uid 0, so `PermitRootLogin prohibit-password` is needed (key only).
- launch_daemon starts sshd at boot, so no startup script is needed. A sshd that's already running keeps its old config: kill it and run `/bin/sshd` (absolute path required).
- `ps` prints `name [args] team threads gid uid`, so the team ID is field `NF-3`.

## Build an hpkg in GitHub CI (no VM of your own)

`cross-platform-actions/action` runs a Haiku R1/beta6 VM on a GitHub runner; a build plus
tests and `package create` took about a minute (Sheath, `.github/workflows/haiku.yml`):

```yaml
- uses: cross-platform-actions/action@v1.6.0
  with:
    operating_system: haiku
    version: r1beta6
    architecture: x86-64
    memory: 4G
    cpu_count: 4
    shell: bash
    run: |
      pkgman install -y gcc make haiku_devel pkgconfig <your>_devel
      sh packaging/build-hpkg.sh
- uses: actions/upload-artifact@v4
  with: { name: app-hpkg, path: '*.hpkg' }
```

The job runs as `user` in a copy of the checkout. Packages from HaikuPorts install with
`pkgman install -y` (e.g. `sword_devel`, which also brings `diatheke`). The same .hpkg
installed and ran on Renku nightly build00055.

**Header differences:** `tools/haiku-typecheck.sh` checks against Haiku's *current* headers,
so it misses things beta6 doesn't have: `AboutWindow.h` (BAboutWindow) is not in beta6's
public headers — use a BAlert. CI on beta6 is the real check.

**pkgman on Renku** may say "A reboot is necessary to complete the installation process"
when a dependency updates system packages (e.g. ICU); `shutdown -r` and reconnect.

## Build an hpkg

The pipeline builds it inside a Haiku R1/beta6 VM with `templates/packaging/build-hpkg.sh`
(release.md § Build the .hpkg). What that script relies on, if you write or debug one:

- **Strip at link time** (`LDFLAGS=-s`): `xres` appends resources after the ELF data, so stripping afterwards removes them.
- **Tree** relative to `/boot/system`: `apps/<App>`, `bin/<cmd>` → `../apps/<App>`, `data/deskbar/menu/Applications/<App>` → `../../../../apps/<App>`, `documentation/packages/<pkg>/`. Run `mimeset -f` on the binary; `package create` keeps attributes.
- **`.PackageInfo`:** `provides { <pkg> = <v>  app:<App> = <v>  cmd:<cmd> }` takes no revision; `requires { haiku >= r1~beta6 }` lets it install on Renku too. `licenses` must name a file in `/boot/system/data/licenses`.
- `finddir B_USER_NONPACKAGED_DIRECTORY` exists, but there's **no** `B_USER_NONPACKAGED_APPS_DIRECTORY` constant. For a `make install`, append `/apps` yourself.

So far packages have been **built** on Haiku beta6 and **tested** on Renku. Building directly on Renku should work the same way, but check that its repositories provide `gcc`/`haiku_devel` first.

## Test checklist (Alt is the command key)

```sh
pkgman install -y ./<pkg>.hpkg               # the dependency check happens here
listattr /boot/system/apps/<App> | grep BEOS # APP_SIG, APP_FLAGS, APP_VERSION, FILE_TYPES, TYPE
(<cmd> > /tmp/app.log 2>&1 &)                # launch with a log
```

The standard release checks are in release-test.md. Platform specifics, for whichever of these the app uses:

- **Shortcuts:** Alt+key = `k:38,<code>,<code|80>,b8` (e.g. Alt+R = `k:38,13,93,b8`).
- **Quit:** `hey <App> quit`. It may print "Error when sending message"; that's harmless.
- **Node monitoring:** with the app running, `mv` a watched file in the Terminal and check that the app noticed.
- **Trash:** `ls $(finddir B_TRASH_DIRECTORY)`, and `catattr _trk/original_path <file>` is what Tracker's Restore uses.
- **Queries:** `lsindex`, then `query '<ATTR>=*value*'`. The app must create its indices (`fs_create_index`) for queries to find anything.
- **File panel:** type-ahead the file name, then Enter.
