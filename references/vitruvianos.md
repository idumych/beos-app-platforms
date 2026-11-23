# VitruvianOS (V\OS)

VitruvianOS (V\OS) is a BeOS-like OS based on Linux: it runs the Haiku API on a Linux kernel, with a Debian trixie userland. Apps ship as `.deb` packages installing to `/system/apps`.

## Compile and link

There are two ways to get headers and libraries:

- **On V\OS itself:** 0.6.x ships headers in `/system/develop/headers`, and newer builds have `pkg-config vos` from `vos-dev`. Link `-lbe -lroot -ltracker -ltranslation`.
  For the 0.6.x headers, add these include dirs: `.`, `os` and `os/*` subdirs, `posix`, `build`, `build/config_headers`, `config`. Also add `-include LinuxBuildCompatibility.h -fPIC`. `templates/Makefile` has the full list.
- **Elsewhere: a link-time SDK** built from VitruvianOS's source by `templates/tools/vos-sdk/make-sdk.sh` (plus `vos-0.6.2-linkonly.patch`), producing `sdk/{include,lib,bin,linkdeps}` and `env.sh`. It runs natively on amd64 or arm64 **Debian trixie** (V\OS's userland, glibc 2.41); on another host, run it in a `debian:trixie` container. Its libraries only prove the link: the app uses the ones installed on V\OS at runtime. The SDK is pinned to 0.6.2 (`VOS_TAG`); apps built on it are tested on the current release (0.6.3). Moving the tag means re-checking the link-only patch against the new source.
- **In CI (release packages, amd64 and arm64):** `templates/.github/workflows/deb.yml` builds natively, not cross: GitHub's free `ubuntu-24.04` and `ubuntu-24.04-arm` runners, each in a `debian:trixie` container, build the SDK (cached per arch) and then the `.deb`. What it learned:
  - **apt build deps:** take the `-dev` list from VitruvianOS's own `.github/workflows/ccpp-arm64.yml` (at the release tag) and drop image tooling and the kits the link-only patch removes (pipewire, gstreamer, bluetooth, nm). With fewer packages, `rc` fails on a missing `FL_LIBRARY` (`libfl-dev`) and libbe on `zlib.h`, one error per run.
  - **Per-arch settings:** `VOS_DYNAMIC_LINKER` = `/lib64/ld-linux-x86-64.so.2` or `/lib/ld-linux-aarch64.so.1`; `-DVITRUVIAN_TARGET_ARCH=amd64|arm64`; header dir `os/arch/x86_64|arm64`.
  - Use `fail-fast: false` so one arch's failure doesn't cancel the other, and don't send cmake/ninja output to `/dev/null`: CI only shows "exit code 1".
  - Both `.deb`s are tested on V\OS in QEMU (Test VMs below); `check-artifact.sh deb` also checks each statically (ELF machine byte at offset 18 = `b7` for arm64, glibc). Releasing: release.md.

Resources: `rc` → `xres -o <bin>` → `resattr -O -o <bin>`. V\OS keeps the app signature both as resources and as attributes. The host-built `xres`/`resattr` need **absolute paths**.

- **`rc` appends `.rsrc` to an output name that lacks it.** `rc x.rdef -o "$(mktemp)"` writes `/tmp/tmp.XXXX.rsrc`, so `xres`/`resattr` then read the empty mktemp file, apply nothing, and still exit 0. Use `mktemp --suffix=.rsrc`. A pile of `/tmp/tmp.*.rsrc` files is the giveaway.
- `xres`/`resattr` on a binary that's **currently running** also fail without an error. Quit the app before re-running a postinst by hand.

## About window: V\OS's own BAboutWindow

Use V\OS's `BAboutWindow` for About on V\OS, not a `BAlert` (the user's choice; PowerPaint
0.1.0 does it). It shows the app icon, name, the version from the app's resources, copyright
lines and a description, as Haiku's apps do. `libbe.so` exports the class, but V\OS keeps
its header in `headers/private/interface`, and the link-time SDK (`make-sdk.sh`) leaves
`headers/private` out, so `#include <AboutWindow.h>` fails in CI.

- Copy `templates/vos/AboutWindow.h` (V\OS's own header, MIT, Haiku, Inc.) into the app,
  e.g. `src/vos/AboutWindow.h`, and set `VOS_INCLUDES := src/vos` in the Makefile. The
  template's V\OS branches add it and define `APP_VOS`; Haiku and Cosmoe never see it.
  Only the class layout matters (vtable, 20 reserved slots, `_reserved[20]`): it's the
  0.6.2 header, the same in 0.6.3. Re-copy it from V\OS's source if a release changes it.
- In the app, behind the define:

      #ifdef APP_VOS
      #include <AboutWindow.h>
      #endif
      …
      void App::AboutRequested()
      {
      #ifdef APP_VOS
          BAboutWindow* about = new BAboutWindow(B_TRANSLATE_SYSTEM_NAME("MyApp"), kAppSig);
          about->AddDescription(B_TRANSLATE("One sentence on what it does."));
          const char* extra[] = { "2026 the MyApp contributors", NULL };
          about->AddCopyright(2022, "Original Author", extra);
          about->AddExtraInfo(B_TRANSLATE("Distributed under the terms of the MIT License."));
          about->Show();
      #else
          … the alert, or Haiku's BAboutWindow (renku.md § Header differences)
      #endif
      }

- The menu item must reach `be_app` (`item->SetTarget(be_app)` or
  `be_app->PostMessage(B_ABOUT_REQUESTED)`), or About does nothing (Test checklist below).
- Test it on V\OS: the window must show the version (`0.1.0`), which an alert never does;
  OCR the screenshot for it.
- Seen with it: `B_TRANSLATE` links `BLocaleRoster::GetCatalog()` from `liblocalestub.a`, which
  older SDKs didn't ship (`make-sdk.sh` now builds and copies it; deb.yml's cache key hashes
  `tools/vos-sdk/*`, so the SDK rebuilds). On a host with Hokku installed, `-llocalestub`
  silently finds `/usr/lib/liblocalestub.a` instead and the link fails or links the wrong
  one: check with `-Wl,--trace`. And `RecentItems.h` (`BRecentFilesList`, in libtracker)
  lives in `os/be_apps/Tracker`, which the template's V\OS branches now search.


`templates/packaging/build-deb.sh` and `postinst.in` do this. What they rely on:

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
- **Upgrading the package removes the item** from the Deskbar (dpkg replaces the add-on file), and it stays gone after a Deskbar restart. So don't add it "once on first run": at every launch, add it unless the user removed it. Record a removal as a marker file in the app's settings folder, written both by the app's own toggle and by the item's "Remove from Deskbar" (the item runs in the Deskbar process, so it can't tell the app directly).
- Give the item its own connection to whatever it monitors, so it works while the app is closed. Ask the app to act through `be_roster->Launch(signature, &message)`: it reaches a running app, or starts it with that message, which may arrive before `ReadyToRun()`, so queue it.
- Draw with `AdoptParentColors()` in `AttachedToWindow()`, and use `SetToolTip()` for the status text.

ivpn-vitruvian's `src/deskbar/` is a worked example.

## Test VMs (QEMU; amd64 and arm64)

Both architectures are tested, in QEMU (no VirtualBox): amd64 under KVM, arm64 in QEMU's
emulated `virt` machine, which is slow (allow minutes to boot, seconds per action). Use the
current release's UEFI images from github.com/VitruvianOS/Vitruvian/releases (0.6.3:
`vos-0.6.3-amd64-uefi-…raw.zst` and `vos-0.6.3-arm64-uefi-…raw.zst`; check the `.sha256`, then
`zstd -d`). **Install onto its own 20 GB+ disk** and test there, never in a live session on a
copy of the image: boot the image as installer media with an empty 20 GB raw disk beside it
and run V\OS's installer. If a release has no installer, ask the user before testing any other
way.

Not yet run with QEMU (the first release that does records the working commands here):

    # amd64: KVM, OVMF, SSH forwarded to the host
    qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4096 -machine q35 \
      -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
      -drive if=pflash,format=raw,file=OVMF_VARS.fd \
      -drive file=disk.img,format=raw,if=virtio -device virtio-vga -device qemu-xhci -device usb-tablet \
      -netdev user,id=n0,hostfwd=tcp:127.0.0.1:<port>-:22 -device virtio-net,netdev=n0 \
      -display none -monitor unix:monitor.sock,server,nowait -qmp unix:qmp.sock,server,nowait
    # arm64: the same with qemu-system-aarch64 -M virt -cpu cortex-a72 (no KVM), edk2's
    # aarch64 firmware (as haiku-arm64-vm.sh uses) and -device ramfb or virtio-gpu

Add `-drive file=<image>.raw,format=raw,if=virtio,snapshot=on` to boot the installer. Start the
VM detached (`setsid nohup … &`), drive it through the monitor and QMP the way `qemu-vm.sh` and
`qmp-input.py` do (screenshots, `sendkey`, absolute pointer), and judge boots by screenshots.

The desktop (coordinates measured at 1280×800 in 0.6.2; check them with `ocr-find.sh`):

- **Boot:** a "Welcome" screen. With VM audio off, an "Installing AudioMixer in Deskbar failed" alert appears; press Enter.
- **User:** the live session's `vos-live` is logged in automatically, with passwordless `sudo`; on the installed system use the account made during installation.
- **Don't** use the text consoles (Ctrl+Alt+F2) and **don't** read the image's `/etc/shadow`: auto mode blocks it as credential exploration. Use the desktop session.
- **Terminal:** click the Deskbar "VitruvianOS" title at (1210,11), then Applications (1040,226), move left (880,226), down to Terminal at about (885,607), and click. Installed apps appear in the same menu.
- **Command key is Ctrl.** Alt+key types the letter instead; undo it with Backspace. Ctrl+Tab doesn't switch windows: quit the app or click the other window.
- **Tools:** no `wget` or `file`; use `curl`. No SSH out of the box; set it up once (below).

## SSH (first time, or when it refuses after a boot)

Open a Terminal on the desktop (above), then type each line and press Enter:

    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    echo '<your public key line>' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
    sudo systemctl enable --now ssh || sudo service ssh start || sudo /usr/sbin/sshd

The keymap is US-International, so check what you typed with `ocr-find.sh shot.png --text`
before pressing Enter. The port forward is QEMU's `hostfwd` above; give each VM its own port.
The emulated arm64 VM can use SSH the same way, just slowly.

## Test checklist

The standard release checks (install, attributes, binary checksum, launch, log, quit) are in release-test.md. Also check `ls /tmp/*.rsrc`: it should not exist (see the rc trap above).

To check which build is installed, hash a file the postinst doesn't touch (the Deskbar add-on, a data file) against the one in the release `.deb` (`ar x x.deb && tar -xf data.tar.*`). The app binary's hash changes on every install, because the postinst writes resources into it with `xres`.

If attributes are missing, reproduce through dpkg itself: `sudo dpkg --unpack x.deb`, add `set -x; exec 2>>/tmp/pi.log` to `/var/lib/dpkg/info/<pkg>.postinst` (and change its `>/dev/null` to the log), then `sudo dpkg --configure <pkg>`. Manual runs from a shell can pass for unrelated reasons (cwd, file names you happened to choose).

Open every menu's items, About included: an item that sends `B_ABOUT_REQUESTED` from a window does nothing unless it's targeted at `be_app` (`item->SetTarget(be_app)`), because `AboutRequested()` lives on the application.

**Apps that need an account** (VPN clients, sync tools): a logged-out test stops at the login screen. Never ask the user for credentials or type them into a VM. Test install, launch, signature and the screens reachable without logging in; list the rest under "Not tested" in the release notes, and offer that the user can log in themselves in the VM.

V\OS specifics (Ctrl+key = `k:1d,<code>,<code|80>,9d`):

- **Node-monitor messages** carry `virtual:node` (node_ref) and `virtual:directory` / `virtual:from directory` / `virtual:to directory` (entry_refs), not Haiku's ints. Handle both, with a path fallback.
- **Trash:** `find_directory(B_TRASH_DIRECTORY)` gives `~/config/data/Trash/files`. Write a freedesktop `.trashinfo` (URL-encoded `Path=`, `DeletionDate=`) into the sibling `info/`, and Tracker's Restore works. GNOME and KDE don't look there, though.
- **No indexing or queries yet.** Attributes are still readable with `getfattr`.
- **File panel quirk:** it shows "0 bytes" for every file. That's a V\OS display quirk, not your app.

## Traps seen in 0.6.2

- **`BWindow::Quit()` from another thread, and `wait_for_thread()`, can return before the
  window's thread is gone.** A plugin or add-on unloaded right after (dlclose) crashes in that
  thread. Keep a `BMessenger` to the window and wait until `IsValid()` is false; don't unload
  code that windows run.
- **The SDK's libroot needs Nexus** ("Can't open Nexus IPC"): binaries built in the CI container
  can't run there. Do anything that must run the app (plugin caches, generated data) in
  `postinst` on the real system.
- **BView calls from another thread abort the app** ("Looper must be locked", even
  `Bounds()`), where Haiku lets reads through. Keep what a non-window thread needs (sizes)
  in your own fields.
- **OpenGL: `BGLView::GetGLProcAddress()` only knows extensions,** not `glBindTexture` and
  other core functions; fall back to `dlsym` on `libOpenGL.so.0`/`libGL.so.1`. BGLView is in
  `/system/lib/libopengl.so` (link `-lopengl`); the link-only SDK in VLC Reborn's
  `tools/vos-sdk` keeps the `opengl` kit for it.
- **Over SSH an app has no session environment**, so it can't reach the sound server
  (PipeWire refuses it). For tests, start it with the desktop's environment:
  `env $(tr '\0' '\n' < /proc/$(pgrep -f Deskbar | head -1)/environ | grep -E '^(XDG_|WAYLAND|DBUS)')`.
