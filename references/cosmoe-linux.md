# Linux via Hokku/Cosmoe (AppImage)

**Use Hokku** (github.com/idumych/hokku, branch `hokku`), the user's fork of Cosmoe (github.com/haydentech/cosmoe, MIT licence). Cosmoe is the Haiku API as a C++ library on X11, Wayland, macOS and Windows; Hokku follows it and adds fixes for freestanding Haiku/Renku app ports. Upstream doesn't accept AI contributions, so:

- **Fix Cosmoe bugs in Hokku, not with workarounds in the app.** Commit the fix to the `hokku` branch (a new commit; don't rewrite it), list it under "Changes from Cosmoe" in Hokku's README, and rebuild the app. Never open issues or pull requests upstream.
- The templates (`templates/`) build against Hokku by default (`COSMOE_REPO`/`COSMOE_TAG` in `haiku-app.env` override it). CI caches the build by the commit the branch points at, so a new Hokku commit rebuilds it (about 15 minutes).

What it is like:

- **No servers.** Wayland and X11 backends are plugins (`libcosmoe-x11.so`, `libcosmoe-wayland.so`), chosen at runtime. Override with `COSMOE_BACKEND=x11|wayland`.
- **Relocatable.** It finds its add-ons (`<libdir>/addons`) and data relative to wherever `libbe.so` is loaded (`dladdr`), which is what makes an AppImage possible.
- **Merged kits.** The translation kit, network kit and others are folded into `libbe`, so link `-lbe -ltracker`.
- **Build from source** (Hokku's `hokku` branch). Cosmoe's prebuilt `.deb`s target Ubuntu 26.04 only.

## Porting traps (check these first)

Rows marked **Fixed in Hokku** need nothing in the app. The others are still open: fix them in Hokku when an app needs it, or work around them.

| Haiku behaviour your code may rely on | On Cosmoe | Do this |
|---|---|---|
| `watch_node(&node_ref, …)` | Upstream: stub, returns `B_NOT_SUPPORTED`; silently no messages | **Fixed in Hokku** (it finds a path for the node from an existing watch or an open `BNode`/`BEntry`). Either way, re-watch folders that move to another directory |
| Node-monitor `device`/`node` are int32/int64 | Upstream: `B_DEVICE_TYPE`/`B_INODE_TYPE` fields | **Fixed in Hokku** (int32/int64, and `FindInt32()`/`FindDevice()` etc. accept either) |
| Node-monitor `name` is a leaf | It's the **full path** | If `name` starts with `/`, use it directly |
| `entry_ref::name` is a leaf | **Full path** (by design: Linux can't find a directory from its node) | Use `BPath(&ref).Leaf()` or `BEntry::GetName()`. Hokku's file panels, Save panel and Open With already show the leaf |
| `B_UNDERSCORE_FACE`, `B_STRIKEOUT_FACE` | Upstream: not drawn, and they select a different (e.g. Light) style | **Fixed in Hokku** (drawn, at the right weight) |
| `be_roster->Launch(&ref)` for folders, files, URLs | Not the Linux desktop | `posix_spawnp("xdg-open", …)` and `waitpid` |
| Zero-length clicks | Upstream: freeze the window for good (a `BMessageRunner` deadlock hit by `BTextView`) | **Fixed in Hokku**. `xtest.sh` still holds clicks for 150 ms |
| Image translators on a first run from a mounted AppImage | With Cosmoe v0.9.0 none loaded, so `GetBitmapFile()` returned NULL all session. Not reproduced since, with Hokku or v0.9.0 | Keep AppRun setting `TRANSLATORS=<bundle>/usr/lib/addons/Translators`. Hokku fixed its colon-splitting off-by-one and prints the directories searched when none load |
| Font faces: `SetFamilyAndFace(family, B_REGULAR_FACE / B_ITALIC_FACE)` | Upstream: every weight below Bold counted as regular, so Regular could come out Thin | **Fixed in Hokku** (Haiku's light/heavy/condensed faces; canonical style names win ties) |
| `SetEventMask(B_POINTER_EVENTS)`, tooltips | Upstream: views in other windows never got pointer events, so tooltips never hid | **Fixed in Hokku** (pointer events delivered app-wide, as on Haiku) |
| `find_directory` | Settings → `~/.config/cosmoe`; Trash → `~/.local/share/Trash/files`; `B_USER_DIRECTORY` → `$HOME`. Cosmoe also creates `~/cosmoe/` | Write `.trashinfo` records (the XDG layout matches V\OS's) |
| Attributes | `user.*` xattrs (plus `user.COSMOE:ATTR_TYPES`); no queries | — |

When a trap is fixed in Hokku, remove the app's workaround and mark the row here.

## Makefile branch

```make
else ifneq ($(wildcard $(COSMOE_ROOT)/include/os/app/Application.h),)
  COSMOE_DIRS := config os os/app os/game os/interface os/kernel os/locale os/media \
                 os/net os/storage os/support os/translation os/be_apps/Tracker \
                 private/interface private/shared private/support posix
  override CXXFLAGS += -I$(COSMOE_ROOT)/include $(addprefix -I$(COSMOE_ROOT)/include/,$(COSMOE_DIRS)) \
                 -DAPP_COSMOE -fPIC
  COSMOE_RPATH ?= $$ORIGIN/../lib
  LIBS := -L$(COSMOE_ROOT)/lib -lbe -ltracker -Wl,-rpath,'$(COSMOE_RPATH)'
  EXTRA_OBJS := obj/App.rsrc.o          # resources are a linked-in section, not xres
```

Resources go in an ELF section named `.cosmoe_rsrc`:

```make
obj/App.rsrc.o: App.rdef
	LD_LIBRARY_PATH=$(COSMOE_ROOT)/lib $(COSMOE_ROOT)/bin/rc -o obj/App.rsrc App.rdef
	cd obj && ld -r -b binary App.rsrc -o App.rsrc.o
	objcopy --rename-section .data=.cosmoe_rsrc --add-section .note.GNU-stack=/dev/null \
		--set-section-flags .note.GNU-stack=noload,readonly obj/App.rsrc.o
```

Cosmoe's own `data/develop/makefile-engine` is the reference for flags. It also links cairo/pango, which a typical app doesn't need. The include root itself must be on the path (`<config/HaikuConfig.h>`, `<private/app/…>`).

## Build Hokku locally (porting and debugging)

```sh
git clone --depth 1 --branch hokku https://github.com/idumych/hokku.git cosmoe-src
cd cosmoe-src && meson setup builddir --prefix=/usr --libdir=lib -Denable_unit_test_compile=false
ninja -C builddir && DESTDIR=<stage> meson install -C builddir --no-rebuild
make COSMOE_ROOT=<stage>/usr && LD_LIBRARY_PATH=<stage>/usr/lib ./App
```

- **Installing.** Upstream Cosmoe hard-codes `/usr/share/wayland-sessions` (a plain `--prefix=$HOME/x` install fails) and its DESTDIR install deletes `libbe.so*` from the host's `/usr/local/lib`. Both are fixed in Hokku; DESTDIR installs work either way.
- **Debug by default.** The default build is a debug build (`libbe` is 27 MB); use `--buildtype=release` for packaging.
- **Arch prerequisites:** `meson` (plus optional `libicns`).
- **Ubuntu prerequisites:** see the apt list in `templates/.github/workflows/appimage.yml`.

## Package an AppImage

`templates/packaging/appimage/build-appimage.sh` (plus `AppRun.in` and `fonts.conf`; it writes the `.desktop` file from `haiku-app.env`) does all of this. What it does, if you debug it:

1. **Build Cosmoe** (release) into a stage. Build the app with `LDFLAGS=-s`; stripping is safe because `.cosmoe_rsrc` is an allocated section.
2. **Assemble the AppDir:** `usr/bin/<App>`, then `libbe.so`, `libtracker.so` and both backend plugins in `usr/lib`. Add `usr/lib/addons/` (Translators, control_look), `usr/share/cosmoe/{mime_db,artwork,locale}`, the Noto fonts the app uses (Regular, Bold, Italic, BoldItalic, Mono), `etc/fonts/fonts.conf`, and the licences (yours plus Cosmoe's `License.md`).
3. **Reset RUNPATHs before linuxdeploy:** `$ORIGIN` for `usr/lib/*.so`, `$ORIGIN/../..` for add-ons. Cosmoe v0.9.0 bakes in `/usr/lib` (newer Cosmoe and Hokku set no RUNPATH on Linux) and linuxdeploy only *appends*, so otherwise the host's ICU, pango and cairo win. linuxdeploy contains a `patchelf`: extract it with `--appimage-extract`.
4. **Run linuxdeploy** with `--executable`, `--deploy-deps-only=` for every add-on and backend, `--desktop-file`, `--icon-file` and `--custom-apprun`. Set `NO_STRIP=1`: its bundled `strip` can't read `.relr.dyn` sections from newer distros.
5. **AppRun:** set `FONTCONFIG_FILE` (a conf that `<include>`s `/etc/fonts/fonts.conf` and adds `<dir prefix="relative">../../usr/share/fonts</dir>`) and `TRANSLATORS`, then `exec` the binary.
6. **Pack:** `appimagetool --no-appstream`. Pin both tools' release tags (e.g. linuxdeploy `1-alpha-20251107-1`, appimagetool `1.9.1`). Set `APPIMAGE_EXTRACT_AND_RUN=1` in CI, which has no FUSE.

**Check the output:**

- `readelf -d squashfs-root/usr/lib/libbe.so | grep RUNPATH` must show only `$ORIGIN`.
- `objdump -T` over all the ELF files gives the minimum glibc/libstdc++. On Ubuntu 24.04 that's GLIBC_2.38 / GLIBCXX_3.4.32, so Ubuntu 24.04, Fedora 39 or Debian 13 and newer.
- `usr/share/doc/` gets the bundled libraries' Debian copyright files automatically on Ubuntu.

**CI:** `templates/.github/workflows/appimage.yml` builds natively on `ubuntu-24.04` (x86_64) and `ubuntu-24.04-arm` (aarch64); `build-appimage.sh` picks linuxdeploy/appimagetool for `uname -m`. Each job caches its Hokku stage (keyed on the commit the branch points at and the arch), starts the AppImage under X11 (`x11-smoke.sh`: Xvfb + Openbox) and Wayland (`wayland-smoke.sh`), uploads `AppImage-<arch>` and `smoke-<arch>`, and on `v*` tags attaches each AppImage only if that file isn't attached yet.

## Headless testing (no VM needed)

The host needs `xorg-server-xvfb`, `openbox`, `xdotool` and ImageMagick.

```sh
Xvfb :99 -screen 0 1280x800x24 -nolisten tcp &   # keep running
DISPLAY=:99 openbox &                            # without a WM, Cosmoe windows get no focus or input
until DISPLAY=:99 xdotool get_desktop >/dev/null 2>&1; do sleep 0.25; done   # WM ready; earlier maps can be lost
APP=./App APP_NAME=App LIBDIR=<stage>/usr/lib sh scripts/xtest.sh start c:600,400 k:ctrl+r shot:a
APP=/path/App-x86_64.AppImage APP_NAME=App sh scripts/xtest.sh start shot:b    # AppImage: no LIBDIR
```

`xtest.sh` keeps the app off the user's desktop: no `WAYLAND_DISPLAY`, `COSMOE_BACKEND=x11`, a throwaway HOME, and a fake `xdg-open` that logs to `$SCRATCH/xdg-open.log`. It also holds clicks for 150 ms. Crop screenshots to the window for READMEs: `import -window root -crop WxH+X+Y +repage`.

**Debugging:**

- **Backtraces:** Yama blocks `gdb -p`, so launch under gdb: `gdb -batch -ex run -ex "thread apply all bt 20" --args ./App`, reproduce, then `pkill -INT -x App`.
- **Library loading:** `LD_DEBUG=files` shows which libraries and add-ons load. `/proc/<pid>/maps` shows whether a library came from `/tmp/.mount_*` (bundled) or `/usr/lib` (host).
- **Timing:** `LD_DEBUG` and gdb slow startup and can hide timing problems, so confirm without them.
- **First run:** test both a **fresh HOME** and a reused one, and both the **mounted** and the extracted AppImage. The v0.9.0 translator failure only showed on a fresh HOME with the mounted image.

Wayland is testable headlessly with **sway** on wlroots' headless backend (`WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway -c <conf>`) and `grim` for screenshots: `templates/packaging/appimage/wayland-smoke.sh`, run by `appimage.yml`. Headless **Weston** doesn't work: it offers no `wl_seat`, and a Cosmoe app opens its window and then exits with status 127. Still not testable headlessly: drag-and-drop from a Linux file manager (XDND). Use a desktop Linux VM (see virtualbox.md) or ask the user to try on their own session.
