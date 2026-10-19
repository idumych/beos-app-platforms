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

Resources: `rc` → `xres -o <bin>` → `resattr -O -o <bin>`. V\OS keeps the app signature both as resources and as attributes. The host-built `xres`/`resattr` need **absolute paths**.

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
(<cmd> > /tmp/app.log 2>&1 &)
```

Then the smoke test in SKILL.md (Ctrl+key = `k:1d,<code>,<code|80>,9d`), with these V\OS specifics:

- **Node-monitor messages** carry `virtual:node` (node_ref) and `virtual:directory` / `virtual:from directory` / `virtual:to directory` (entry_refs), not Haiku's ints. Handle both, with a path fallback.
- **Trash:** `find_directory(B_TRASH_DIRECTORY)` gives `~/config/data/Trash/files`. Write a freedesktop `.trashinfo` (URL-encoded `Path=`, `DeletionDate=`) into the sibling `info/`, and Tracker's Restore works. GNOME and KDE don't look there, though.
- **No indexing or queries yet.** Attributes are still readable with `getfattr`.
- **File panel quirk:** it shows "0 bytes" for every file. That's a V\OS display quirk, not your app.
