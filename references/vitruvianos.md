# VitruvianOS (V\OS)

V\OS runs the Haiku API on a Linux kernel, on a Debian trixie userland. Apps ship as `.deb` packages installing to `/system/apps`.

## Compile and link

There are two ways to get headers and libraries:

- **On V\OS itself:** 0.6.x ships headers in `/system/develop/headers`, and newer builds have `pkg-config vos` from `vos-dev`. Link `-lbe -lroot -ltracker -ltranslation`.
  For the 0.6.x headers, add these include dirs: `.`, `os` and `os/*` subdirs, `posix`, `build`, `build/config_headers`, `config`. Also add `-include LinuxBuildCompatibility.h -fPIC`. Folio's Makefile has the full list.
- **On a plain Linux host:** build a link-time SDK from VitruvianOS's source. Folio's `tools/vos-sdk/make-sdk.sh` (plus `vos-0.6.2-linkonly.patch`) does it in about 4 minutes and produces `.vos-sdk/sdk/{include,lib,bin,linkdeps}` and `env.sh`. Reuse it:
  - It needs `git cmake ninja g++ gcc bison m4 make pkg-config`. A shell *alias* for ninja doesn't count; the binary must exist.
  - Arch-family hosts report the compiler triple `x86_64-pc-linux-gnu`, which VitruvianOS's `engine.cmake` rejects. Pass `-DVOS_DYNAMIC_LINKER=/lib64/ld-linux-x86-64.so.2`.
  - These libraries only prove the link. The app uses the ones installed on V\OS at runtime.
- **In CI (preferred for release packages; amd64 and arm64):** build natively, not cross. GitHub's free `ubuntu-24.04` and `ubuntu-24.04-arm` runners, each in a `debian:trixie` container (V\OS's userland, glibc ≤ 2.41), build the SDK with an arch-aware `make-sdk.sh` and then the `.deb`. ivpn-vitruvian (github.com/idumych/ivpn-vitruvian) is the template: `.github/workflows/build.yml` and `tools/vos-sdk/make-sdk.sh`.
  - **apt build deps:** take the `-dev` list from VitruvianOS's own `.github/workflows/ccpp-arm64.yml` (at the release tag) and drop image tooling and the kits the link-only patch removes (pipewire, gstreamer, bluetooth, nm). With fewer packages, `rc` fails on a missing `FL_LIBRARY` (`libfl-dev`) and libbe on `zlib.h`, one error per run.
  - **Per-arch settings:** `VOS_DYNAMIC_LINKER` = `/lib64/ld-linux-x86-64.so.2` or `/lib/ld-linux-aarch64.so.1`; `-DVITRUVIAN_TARGET_ARCH=amd64|arm64`; header dir `os/arch/x86_64|arm64`. With every dep from apt, Folio's ICU/flex/systemd bootstrapping isn't needed.
  - Use `fail-fast: false` so one arch's failure doesn't cancel the other, and don't send cmake/ninja output to `/dev/null`: CI only shows "exit code 1".
  - **Releases:** let the tag-triggered run create the release as a **prerelease** and attach the `.deb`s + `SHA256SUMS`. Test from those URLs in the VM, then `gh release edit <tag> --prerelease=false --latest`. VirtualBox can't run arm64 guests on an x86 host, so arm64 gets static checks only (ELF machine byte at offset 18 = `b7`, glibc), and the release notes say so.

Resources: `rc` → `xres -o <bin>` → `resattr -O -o <bin>`. V\OS keeps the app signature both as resources and as attributes. The host-built `xres`/`resattr` need **absolute paths**.

- **`rc` appends `.rsrc` to an output name that lacks it.** `rc x.rdef -o "$(mktemp)"` writes `/tmp/tmp.XXXX.rsrc`, so `xres`/`resattr` then read the empty mktemp file, apply nothing, and still exit 0. Use `mktemp --suffix=.rsrc`. A pile of `/tmp/tmp.*.rsrc` files is the giveaway.
- `xres`/`resattr` on a binary that's **currently running** also fail without an error. Quit the app before re-running a postinst by hand.

## Package a .deb

Folio's `packaging/build-deb.sh` is a template. The parts that matter:

- **Strip at link time** (`LDFLAGS=-s`). `xres` appends the resources, so a later strip would remove them.
- **dpkg drops extended attributes,** and V\OS keeps BEOS attributes as `user.beos.*` xattrs. Ship them in a tarball (`/usr/share/<pkg>/apps_attrs.tar`) and restore them in `postinst` with `getfattr`/`setfattr`; that's how V\OS's own package does it. Add `BEOS:TYPE` = `application/x-vnd.Be-elfexecutable`, stored as `MIMS` + the NUL-terminated string.
- **Layout:** `/system/apps/<App>`, a Deskbar link at `/system/data/deskbar/menu/Applications/<App>`, and `/usr/bin/<cmd>` as a link.
- **Pin the OS version:** `Depends: vos (>= 0.6.2), vos (<< 0.7~)`. The Haiku API is C++, so class layouts may change between releases.
- **Check glibc** against trixie: `objdump -T <bin> | grep -oE 'GLIBC[XX]*_[0-9.]+' | sort -Vu`. GLIBC ≤ 2.41 is fine.
- **Tools:** `dpkg-deb` comes from the `dpkg` package (Arch: `pacman -S dpkg`). Build with `dpkg-deb --root-owner-group -Zxz --build`.
- **Verify the result:**
  - `dpkg-deb -I` / `-c` for the control fields and file list.
  - The signature is still in the binary: `dpkg-deb --fsys-tarfile x.deb | tar -xO ./system/apps/<App> | strings -a | grep -c <signature>`.
  - Extract the attributes tarball **into a scratch dir**; extracting it next to the binary overwrites the binary with the empty placeholder.

## Deskbar tray items

A tray item (status icon) is a view that Deskbar loads from an add-on. On Linux, glibc won't `dlopen` a PIE executable, so either link the app as a "runnable add-on" (VitruvianOS's `RunnableAddOn` CMake macro: `-shared` plus a `.interp` section and `Scrt1.o`, the way NetworkStatus does it) or, simpler, ship a **separate add-on library**:

- Build it from `-fPIC` objects: `g++ -shared -o Item.so *.o -Wl,--no-undefined -lbe -lroot`. `--no-undefined` turns a missing symbol into a build error instead of a Deskbar crash. Install it somewhere like `/system/add-ons/<pkg>/`.
- Export `extern "C" _EXPORT BView* instantiate_deskbar_item(float maxWidth, float maxHeight)`.
- **The view must be archivable.** Deskbar's `TReplicantTray::LoadAddOn()` calls your function, then archives the view and rebuilds it through `BShelf::AddReplicant()` → `instantiate_object()`. Give the view a `BView(BMessage*)` constructor, a `static BArchivable* Instantiate(BMessage*)` (with `validate_instantiation`), and `Archive()`. Without them nothing appears, and the journal shows `Deskbar[pid]: instantiate_object failed: No signature specified in archive, looking for class "…"`.
- **Use a unique class name** (`MyAppDeskbarView`): every tray add-on lives in the Deskbar process, and `instantiate_object` looks classes up by name.
- `LoadAddOn()` **ignores** `AddIcon()`'s failure, so `BDeskbar::AddItem(&ref)` returns `B_OK` even when nothing appeared. Check the tray, and `journalctl -b | grep -i deskbar`.
- **A failed add-on stays loaded** in Deskbar, and glibc hands back the cached image for the same path, so a fixed build isn't picked up until Deskbar restarts: `quit application/x-vnd.Be-TSKB`, then, because the session manager doesn't relaunch it, `setsid /system/Deskbar >/dev/null 2>&1 &`. Each failed attempt also adds the path to `~/config/settings/deskbar/replicants`; duplicates are skipped later.
- There is no `desklink` on VitruvianOS; add the item from the app (`BDeskbar().AddItem(&ref)`, `HasItem(name)`, `RemoveItem(name)`).
- Give the item its own connection to whatever it monitors, so it works while the app is closed. Ask the app to act through `be_roster->Launch(signature, &message)`: it reaches a running app, or starts it with that message, which may arrive before `ReadyToRun()`, so queue it.
- Draw with `AdoptParentColors()` in `AttachedToWindow()`, and use `SetToolTip()` for the status text.

ivpn-vitruvian's `src/deskbar/` is a worked example.

## Make a test VM

The images are raw **UEFI** disks (e.g. `vitruvian-0.6.2-amd64.raw`):

```sh
sh scripts/make-vm.sh <name> ~/Downloads/vitruvian-0.6.2-amd64.raw efi
```

The live session runs at 1280×800.

- **Boot:** "Welcome" screen → **Try It Now** (Enter, or a click at about (900,582)). With VM audio off, an "Installing AudioMixer in Deskbar failed" alert appears; press Enter.
- **User:** `vos-live`, logged in automatically, with passwordless `sudo`.
- **Don't** use the text consoles (Ctrl+Alt+F2) and **don't** read the image's `/etc/shadow`: auto mode blocks it as credential exploration. Use the desktop session.
- **Terminal:** click the Deskbar "VitruvianOS" title at (1210,11), then Applications (1040,226), move left (880,226), down to Terminal at about (885,607), and click. Installed apps appear in the same menu.
- **Command key is Ctrl.** Alt+key types the letter instead; undo it with Backspace `k:0e,8e`. Ctrl+Tab doesn't switch windows: quit the app or click the other window.
- **Tools:** no `wget` or `file`; use `curl`. There's no SSH, so use the release URLs or a LAN-IP HTTP server for files.
- **Persistence:** writes to the live session survive a VM restart (the VDI is writable). The welcome screen comes back each boot.

## Test checklist

```sh
cd /tmp && curl -fsSLO <release URL>/<pkg>_<v>-1_amd64.deb && sha256sum <pkg>_*.deb
sudo apt install -y ./<pkg>_<v>-1_amd64.deb && dpkg -s <pkg> | grep Version
getfattr -d -m user.beos /system/apps/<App>      # signature attributes restored?
ls /tmp/*.rsrc                                   # should not exist (see the rc trap above)
(<cmd> > /tmp/app.log 2>&1 &)
```

If attributes are missing, reproduce through dpkg itself: `sudo dpkg --unpack x.deb`, add `set -x; exec 2>>/tmp/pi.log` to `/var/lib/dpkg/info/<pkg>.postinst` (and change its `>/dev/null` to the log), then `sudo dpkg --configure <pkg>`. Manual runs from a shell can pass for unrelated reasons (cwd, file names you happened to choose).

Open every menu's items, About included: an item that sends `B_ABOUT_REQUESTED` from a window does nothing unless it's targeted at `be_app` (`item->SetTarget(be_app)`), because `AboutRequested()` lives on the application.

**Apps that need an account** (VPN clients, sync tools): a logged-out test stops at the login screen. Never ask the user for credentials or type them into a VM. Test install, launch, signature and the screens reachable without logging in; list the rest under "Not tested" in the release notes, and offer that the user can log in themselves in the VM.

Then the smoke test in SKILL.md (Ctrl+key = `k:1d,<code>,<code|80>,9d`), with these V\OS specifics:

- **Node-monitor messages** carry `virtual:node` (node_ref) and `virtual:directory` / `virtual:from directory` / `virtual:to directory` (entry_refs), not Haiku's ints. Handle both, with a path fallback.
- **Trash:** `find_directory(B_TRASH_DIRECTORY)` gives `~/config/data/Trash/files`. Write a freedesktop `.trashinfo` (URL-encoded `Path=`, `DeletionDate=`) into the sibling `info/`, and Tracker's Restore works. GNOME and KDE don't look there, though.
- **No indexing or queries yet.** Attributes are still readable with `getfattr`.
- **File panel quirk:** it shows "0 bytes" for every file. That's a V\OS display quirk, not your app.
