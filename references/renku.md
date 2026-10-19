# Renku OS (and Haiku-family guests)

Renku OS (github.com/RenkuOS/Source) is a fork of Haiku that started in September 2026. For packaging it's still Haiku:

- **Package name and version.** The system package is still called `haiku`, with `HAIKU_VERSION = r1~beta6` (`build/jam/BuildSetup`). A package that `requires { haiku >= r1~beta6 }` installs on both Haiku R1/beta6 and Renku. A binary built on Haiku beta6 ran unchanged on Renku nightly build00055 (hrev60072+253).
- **Nightlies:** `gh release view nightly -R RenkuOS/Source` (x86_64 and x86_gcc2h ISOs, each with a `.sha256`). Download into `~/Downloads` and check with `sha256sum -c`.
- **Policy:** `AGENTS.md` in RenkuOS/Source, plus `RenkuOS/PlanAndGovernance` (CONTRIBUTING, REVIEW, DECISIONS). Machine-assisted work is allowed. Pull requests need a short human-style summary, a "How this was tested" section and a DCO `Signed-off-by`. Issues go to RenkuOS/Source. Renku has its own package repository ("Spritz Depot"); see its open issues for the submission process.

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

## Build an hpkg

Inside the guest, `pkgman install gcc make haiku_devel` (only what's missing). Then from the host:

```sh
git archive HEAD | ssh <alias> 'rm -rf ~/rel && mkdir ~/rel && tar -x -C ~/rel && cd ~/rel && make hpkg'
scp <alias>:rel/<pkg>.hpkg .
```

The pattern a packaging script should follow (Folio's `packaging/haiku/build-hpkg.sh` is a template):

1. **Build with `LDFLAGS=-s`.** `xres` appends resources after the ELF data, so stripping afterwards would remove them.
2. **Lay out a tree** relative to `/boot/system`: `apps/<App>`, `bin/<cmd>` (link `../apps/<App>`), `data/deskbar/menu/Applications/<App>` (link `../../../../apps/<App>`), and `documentation/packages/<pkg>/`.
3. **Run `mimeset -f`** on the binary. `package create` keeps attributes.
4. **Write `.PackageInfo`:**
   - `name`, `version <v>-<rev>`, `architecture $(getarch)`
   - `summary`, `description`, `packager`, `vendor`, `copyrights`, `licenses`, `urls`
   - `provides { <pkg> = <v>  app:<App> = <v>  cmd:<cmd> }` (no revision in `provides`)
   - `requires { haiku >= r1~beta6 }`
5. **Pack it:** `package create -C <tree> <out>.hpkg`. Verify with `package list <out>.hpkg`.

`finddir B_USER_NONPACKAGED_DIRECTORY` exists, but there's **no** `B_USER_NONPACKAGED_APPS_DIRECTORY` constant. For a `make install`, append `/apps` yourself.

So far packages have been **built** on a Haiku beta6 VM and **tested** on Renku. Building directly on Renku should work the same way, but check that its repositories provide `gcc`/`haiku_devel` first.

## Test checklist (Alt is the command key)

```sh
pkgman install -y ./<pkg>.hpkg               # the dependency check happens here
listattr /boot/system/apps/<App> | grep BEOS # APP_SIG, APP_FLAGS, APP_VERSION, FILE_TYPES, TYPE
(<cmd> > /tmp/app.log 2>&1 &)                # launch with a log
```

Then the smoke test in SKILL.md, plus whichever of these the app uses:

- **Shortcuts:** Alt+key = `k:38,<code>,<code|80>,b8` (e.g. Alt+R = `k:38,13,93,b8`).
- **Quit:** `hey <App> quit`. It may print "Error when sending message"; that's harmless.
- **Node monitoring:** with the app running, `mv` a watched file in the Terminal and check that the app noticed.
- **Trash:** `ls $(finddir B_TRASH_DIRECTORY)`, and `catattr _trk/original_path <file>` is what Tracker's Restore uses.
- **Queries:** `lsindex`, then `query '<ATTR>=*value*'`. The app must create its indices (`fs_create_index`) for queries to find anything.
- **File panel:** type-ahead the file name, then Enter.
