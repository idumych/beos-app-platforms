> **No VirtualBox any more** (SKILL.md § Rules): run VMs in QEMU with `scripts/qemu-vm.sh`. The VirtualBox steps below are kept only for what carries over (scancodes, guest-side setup, screenshot hygiene).

# Renku OS (and Haiku-family guests)

Renku OS (github.com/RenkuOS/Source) is a fork of Haiku that started in September 2026. For packaging it's still Haiku:

- **Package name and version.** The system package is still called `haiku`, with `HAIKU_VERSION = r1~beta6` (`build/jam/BuildSetup`). A package that `requires { haiku >= r1~beta6 }` installs on both Haiku R1/beta6 and Renku. A binary built on Haiku beta6 ran unchanged on Renku nightly build00055 (hrev60072+253).
- **Nightlies:** `gh release view nightly -R RenkuOS/Source` (x86_64 and x86_gcc2h ISOs, an arm64 `.img.zst` for QEMU, and each architecture's repository as a `.tar`, each with a `.sha256`). Download into `~/Downloads` and check with `sha256sum -c`. Some nights only the x86_gcc2h ISO is attached, so there may be no x86_64 image until a later build.
- **Policy:** `AGENTS.md` in RenkuOS/Source, plus `RenkuOS/PlanAndGovernance` (CONTRIBUTING, REVIEW, DECISIONS). Machine-assisted work is allowed. Pull requests need a short human-style summary, a "How this was tested" section and a DCO `Signed-off-by`. Issues go to RenkuOS/Source. Renku has its own package repository ("Spritz Depot"); see its open issues for the submission process.

## Renku's repositories (Renku OS only)

Renku publishes its own package repositories, all built from one Renku build (Nov 2026:
`r1~beta6_hrev60072_940`):

| Repository | URL | Has |
|---|---|---|
| System, x86_64 | `https://renkuos.freemyip.com/repo/x86_64` | `haiku`, `haiku_devel`, `haiku_loader`, `haiku_extras`, `haiku_datatranslators`, `makefile_engine`, `netfs`, `userland_fs`, `webpositive` |
| System, arm64 | `https://renkuos.freemyip.com/repo/arm64` | the same, without WebPositive |
| System, x86_gcc2 (32-bit hybrid) | `https://renkuos.freemyip.com/repo/x86_gcc2` | the same plus `haiku_x86`, `haiku_x86_devel`, `webpositive_x86` |
| Ports (RenkuOSPorts) | `https://renkuos.freemyip.com/repo/renkuosports/<arch>` | HaikuPorts recipes built for Renku |

- **Use them only with Renku OS.** Add them (`pkgman add-repo <url>`) on Renku systems, and use
  their packages only in builds that target Renku (the arm64 sysroot). Never add them to a
  Haiku VM or mix their packages into a build meant for Haiku.
- Each repository's page lists its packages, the files are under `<url>/packages/`, and
  `<url>/repo.info` names the build. The same repositories ship as `renkuos-<arch>-repo.tar` with
  each nightly (`gh release view nightly -R RenkuOS/Source`).
- `haiku_devel` is in the system repository, so on Renku `pkgman install haiku_devel` gives the
  headers for the installed build when the image and the repository are the same build. Check
  `pkgman search -a haiku` against `uname -v` first (§ Build an hpkg, for when they differ).

## arm64

arm64 apps target **Renku OS**, not Haiku. Haiku has no R1/beta6 arm64 release, and arm64 builds
no longer use Haiku's master repository or its nightlies. Renku has all three pieces:

- **System packages:** `haiku` and `haiku_devel` in its arm64 system repository (above). The
  sysroot is made from them (haiku-arm64.md).
- **Ports:** RenkuOSPorts arm64 (`https://renkuos.freemyip.com/repo/renkuosports/arm64/`, built
  natively in QEMU from `RenkuOS/RenkuOSPorts` `renkuos/bootstrap/arm64`): about 340 ports,
  among them `gcc_syslibs`, `icu74`, `zlib`, openssl3, opus, libogg, ffmpeg 6/8, libjpeg_turbo,
  libpng16, libwebp and SDL2, but no tdlib. Check its list at each release:

      curl -s https://renkuos.freemyip.com/repo/renkuosports/arm64/ | grep -oE 'packages/[^"]+' | sed 's|packages/||'

- **A test system:** Renku's nightly has an arm64 image for QEMU's `virt` machine,
  `RenkuOS-arm64-<date>-build<NNN>.img.zst` (decompress with `zstd -d`). It's Tier 2 ("ships
  when it boots") and has no clock driver, so its clock starts in 1970. Its partition layout is
  the same as Haiku's arm64 image, so `scripts/haiku-arm64-vm.sh` installs it onto a 20 GB disk
  (haiku-arm64.md § Test). build00090's first boot works but every later boot of the same image hangs (RenkuOS/Source#480,
  haiku-arm64.md § Test).

      gh release view nightly -R RenkuOS/Source --json assets -q '.assets[].name' | grep arm64

## Make a test VM

```sh
sh scripts/make-vm.sh <name> ~/Downloads/RenkuOS-x86_64-<date>-build<NNN>.iso     # VirtualBox
DIR=~/VMs/<name> sh scripts/qemu-vm.sh create ~/Downloads/RenkuOS-x86_64-….iso   # or QEMU/KVM
DIR=~/VMs/<name> sh scripts/qemu-vm.sh start
```

Use QEMU when the user prefers it or VirtualBox misbehaves; it's also the way to capture
the guest's audio output exactly (`AUDIO=wav`, media-kit.md § Testing). Under QEMU's
`-vga std` the screen is 1280×800 (set `QW=1280 QH=800` for the pointer, which
qemu-vm.sh does), the usb-tablet pointer takes absolute clicks, and Renku writes kernel
output to the serial log without the boot-menu option. KVM fails while any VirtualBox VM
is running: power those off first (and stop any background loop that restarts them).

The ISO is an *anyboot* hybrid image, so converted to VDI it boots as a writable hard disk with BIOS firmware. The screen is 1024×768. The same applies to Haiku's own anyboot images.

- **First screen:** "Welcome!", with **Try it out** at about (778,566). It leads to the desktop, logged in, with the Deskbar top-right.
- **Terminal:** click the Deskbar logo at (955,12), hover Applications (785,226), move left (640,226), go down to Terminal at about (625,707), then click. Screenshot first; positions shift as the menu changes.
- **Free space:** about 300 MB on the boot disk. Packages stay compressed, so `pkgman install gcc make` fits. `haiku_devel` was already installed on the Haiku beta6 image; Renku nightlies lack it (§ Build an hpkg).
- **Clock:** the VM clock runs in local time while the host assumes UTC, so tar and make warn "time stamp in the future". Fix with `find . -exec touch {} +`, or rely on `make clean`.
- **Screen blanker:** if a screenshot is black, move the mouse (`m:move,…`) and take it again.

### When it hangs on the boot splash

Symptom: the splash with all icons lit (or a black screen) forever; the kernel debugger's
`teams` shows no `app_server` and `media_server` with a team ID in the tens of thousands,
restarting in a loop inside `runtime_loader` (page fault, `bt` ends in `load_program`).

- **Renku hrev60072+355 (build00064), Oct 2026: a freshly copied image boots; every later
  boot of the same disk hangs**, in VirtualBox and in QEMU alike (6 of 6 reboots). So copy
  the ISO again for each boot (`qemu-vm.sh create`, or a new VDI), and redo SSH and
  toolchain setup, or keep the VM running between sessions. The cause isn't known yet;
  if it's still there on a newer nightly, it's worth a RenkuOS/Source issue (ask the user).
- Haiku R1/beta6 (hrev59866+79) showed the same hang on most boots in VirtualBox 7.2.22,
  whatever the disk controller, graphics, CPU count, audio or second disk; nightly
  hrev59741 booted every time. It's not a VirtualBox bug, and the audio driver setting
  doesn't change it.

To look inside:

1. **Serial log:** VirtualBox: with the VM off, `VBoxManage modifyvm <vm> --uart1 0x3F8 4 --uartmode1 file <path>`. Haiku beta6 doesn't log to serial by default: press Space repeatedly right after starting (`k:39,b9`) to get the boot menu, then **Select debug options → Enable serial debug output** → Return → **Continue booting** (lasts one boot). QEMU: qemu-vm.sh always writes `$DIR/serial.log`.
2. **Kernel debugger:** Alt+SysRq+D = `k:38,54,20,a0,d4,b8` in vm.sh, `key alt-sysrq-d` in qemu-vm.sh. Type commands and Enter; output goes to the serial log. Useful ones: `teams`, `threads <team>`, `bt <thread>`, `syslog | grep <word>`, `syslog | tail 30`.

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
public headers, but the class is in libbe and `haiku_devel` ships its private header, so
use it with a fallback (PowerPlay does):

    #if __has_include(<AboutWindow.h>)
    #	include <AboutWindow.h>
    #else
    #	include <private/interface/AboutWindow.h>
    #endif

Renku is making the header public (RenkuOS/Source branch `public-about-window`). CI on
beta6 is the real check.

**pkgman on Renku** may say "A reboot is necessary to complete the installation process"
when a dependency updates system packages (e.g. ICU); `shutdown -r` and reconnect.

## Build an hpkg

The pipeline builds it inside a Haiku R1/beta6 VM with `templates/packaging/build-hpkg.sh`
(release.md § Build the .hpkg). What that script relies on, if you write or debug one:

- **Strip at link time** (`LDFLAGS=-s`): `xres` appends resources after the ELF data, so stripping afterwards removes them.
- **Tree** relative to `/boot/system`: `apps/<App>`, `bin/<cmd>` → `../apps/<App>`, `data/deskbar/menu/Applications/<App>` → `../../../../apps/<App>`, `documentation/packages/<pkg>/`. Run `mimeset -f` on the binary; `package create` keeps attributes.
- **`.PackageInfo`:** `provides { <pkg> = <v>  app:<App> = <v>  cmd:<cmd> }` takes no revision; `requires { haiku >= r1~beta6 }` lets it install on Renku too. `licenses` must name a file in `/boot/system/data/licenses`.
- **Apps that are HaikuPorts ports** (VLC and other autotools apps with a recipe) are built
  with `haikuporter` from the app's recipe instead. It reuses an old `work-*` directory and then
  skips the patchset: delete it first. After killing a build, its chroot mounts stay: `unmount
  work-*/dev` and `work-*/boot/system` before `rm -rf`. `haikuporter -C` (no chroot) doesn't
  work on Haiku.
- `finddir B_USER_NONPACKAGED_DIRECTORY` exists, but there's **no** `B_USER_NONPACKAGED_APPS_DIRECTORY` constant. For a `make install`, append `/apps` yourself.

So far packages have been **built** on Haiku beta6 and **tested** on Renku. Building directly on Renku works (JamesDSP's media add-on, Oct 2026) with one catch:

**`haiku_devel` can lag the nightly.** The Renku image has no system headers or startup
objects. Install `haiku_devel` from Renku's system repository (§ Renku's repositories) when it
is the image's build. It once was older (hrev60072_341 against the image's …_355), and then
`pkgman install haiku_devel` only offers to downgrade the system package, which needs a reboot
(and reboots hung, above). Don't. Download the package and extract it next to the toolchain
instead:

```sh
pkgman install -y gcc make
mkdir -p ~/devel/sys && cd ~/devel
curl -fsSLO https://renkuos.freemyip.com/repo/x86_64/packages/haiku_devel-<version>-x86_64.hpkg
package extract -C sys haiku_devel-*.hpkg
D=~/devel/sys/develop
INC="-idirafter $D/headers/posix -idirafter $D/headers -idirafter $D/headers/os"
for d in $D/headers/os/*/; do INC="$INC -idirafter $d"; done
make CPPFLAGS="-B$D/lib/ $INC" LDFLAGS="-B$D/lib/ -L/boot/system/lib"
```

`-B` finds `crti.o`/`crtn.o`/`init_term_dyn.o`; the libraries link from `/boot/system/lib`
(the package's `develop/lib` symlinks point outside the extracted tree). Use `-idirafter`,
not `-isystem`: libstdc++'s `<cstdlib>` does `#include_next <stdlib.h>`, which fails
when the system headers come before gcc's own.

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
