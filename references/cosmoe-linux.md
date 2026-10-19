# Linux via Cosmoe (AppImage)

Cosmoe (github.com/haydentech/cosmoe, MIT licence) is the Haiku API as a C++ library on X11, Wayland, macOS and Windows:

- **No servers.** Wayland and X11 backends are plugins (`libcosmoe-x11.so`, `libcosmoe-wayland.so`), chosen at runtime. Override with `COSMOE_BACKEND=x11|wayland`.
- **Relocatable.** It finds its add-ons (`<libdir>/addons`) and data relative to wherever `libbe.so` is loaded (`dladdr`), which is what makes an AppImage possible.
- **Merged kits.** The translation kit, network kit and others are folded into `libbe`, so link `-lbe -ltracker`.
- **Pin a release tag** (e.g. `v0.9.0_20261013`) and build from source. Cosmoe's prebuilt `.deb`s target Ubuntu 26.04 only.

## Porting traps (check these first)

| Haiku behaviour your code may rely on | On Cosmoe | Do this |
|---|---|---|
| `watch_node(&node_ref, …)` | Stub, returns `B_NOT_SUPPORTED`; silently no messages (cosmoe#2) | Use `watch_path(absPath, flags, messenger)`, and re-watch folders after they move (path watches don't follow renames) |
| Node-monitor `device`/`node` are int32/int64 | `B_DEVICE_TYPE`/`B_INODE_TYPE` fields (cosmoe#2) | Read them type-agnostically (`GetInfo` + `FindData`, take 4 or 8 bytes) |
| Node-monitor `name` is a leaf | It's the **full path** (cosmoe#2) | If `name` starts with `/`, use it directly |
| `entry_ref::name` is a leaf | **Full path** (cosmoe#6) | Use `BPath(&ref).Leaf()` or a basename. Set file-panel titles yourself, or they read `/path/to/App: Open` |
| `B_UNDERSCORE_FACE`, `B_STRIKEOUT_FACE` | Not drawn, and they select a different (e.g. Light) style (cosmoe#3) | Leave them out on Cosmoe; use colour |
| `be_roster->Launch(&ref)` for folders, files, URLs | Not the Linux desktop | `posix_spawnp("xdg-open", …)` and `waitpid` |
| Zero-length clicks | Stop all input to the window for good (cosmoe#5) | Nothing to fix in the app; hold clicks for 150 ms in tests |
| Image translators on a first run from a mounted AppImage | None load, so `GetBitmapFile()` returns NULL all session (cosmoe#4) | Have AppRun set `TRANSLATORS=<bundle>/usr/lib/addons/Translators` (a single path: `AddPaths()` drops a character from all but the last entry) |
| `find_directory` | Settings → `~/.config/cosmoe`; Trash → `~/.local/share/Trash/files`; `B_USER_DIRECTORY` → `$HOME`. Cosmoe also creates `~/cosmoe/` | Write `.trashinfo` records (the XDG layout matches V\OS's) |
| Attributes | `user.*` xattrs (plus `user.COSMOE:ATTR_TYPES`); no queries | — |

Check the open issues on haydentech/cosmoe before relying on a workaround, and drop it once the pinned tag includes a fix.

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

## Build Cosmoe locally (porting and debugging)

```sh
git clone --depth 1 --branch <tag> https://github.com/haydentech/cosmoe.git cosmoe-src
cd cosmoe-src && meson setup builddir --prefix=/usr --libdir=lib -Denable_unit_test_compile=false
ninja -C builddir && DESTDIR=<stage> meson install -C builddir --no-rebuild
make COSMOE_ROOT=<stage>/usr && LD_LIBRARY_PATH=<stage>/usr/lib ./App
```

- **Install with DESTDIR.** A plain `--prefix=$HOME/x` install fails, because Cosmoe hard-codes `/usr/share/wayland-sessions` (cosmoe#7).
- **Debug by default.** The default build is a debug build (`libbe` is 27 MB); use `--buildtype=release` for packaging.
- **Arch prerequisites:** `meson` (plus optional `libicns`).
- **Ubuntu prerequisites:** see the apt list in Folio's `.github/workflows/appimage.yml`.

## Package an AppImage

Folio's `packaging/appimage/build-appimage.sh` (plus `AppRun`, `fonts.conf`, a `.desktop` file and an icon) is a working template. Steps:

1. **Build Cosmoe** (release) into a stage. Build the app with `LDFLAGS=-s`; stripping is safe because `.cosmoe_rsrc` is an allocated section.
2. **Assemble the AppDir:** `usr/bin/<App>`, then `libbe.so`, `libtracker.so` and both backend plugins in `usr/lib`. Add `usr/lib/addons/` (Translators, control_look), `usr/share/cosmoe/{mime_db,artwork,locale}`, the Noto fonts the app uses (Regular, Bold, Italic, BoldItalic, Mono), `etc/fonts/fonts.conf`, and the licences (yours plus Cosmoe's `License.md`).
3. **Reset RUNPATHs before linuxdeploy:** `$ORIGIN` for `usr/lib/*.so`, `$ORIGIN/../..` for add-ons. Cosmoe bakes in `/usr/lib` and linuxdeploy only *appends*, so otherwise the host's ICU, pango and cairo win. linuxdeploy contains a `patchelf`: extract it with `--appimage-extract`.
4. **Run linuxdeploy** with `--executable`, `--deploy-deps-only=` for every add-on and backend, `--desktop-file`, `--icon-file` and `--custom-apprun`. Set `NO_STRIP=1`: its bundled `strip` can't read `.relr.dyn` sections from newer distros.
5. **AppRun:** set `FONTCONFIG_FILE` (a conf that `<include>`s `/etc/fonts/fonts.conf` and adds `<dir prefix="relative">../../usr/share/fonts</dir>`) and `TRANSLATORS`, then `exec` the binary.
6. **Pack:** `appimagetool --no-appstream`. Pin both tools' release tags (e.g. linuxdeploy `1-alpha-20251107-1`, appimagetool `1.9.1`). Set `APPIMAGE_EXTRACT_AND_RUN=1` in CI, which has no FUSE.

**Check the output:**

- `readelf -d squashfs-root/usr/lib/libbe.so | grep RUNPATH` must show only `$ORIGIN`.
- `objdump -T` over all the ELF files gives the minimum glibc/libstdc++. On Ubuntu 24.04 that's GLIBC_2.38 / GLIBCXX_3.4.32, so Ubuntu 24.04, Fedora 39 or Debian 13 and newer.
- `usr/share/doc/` gets the bundled libraries' Debian copyright files automatically on Ubuntu.

**CI:** build on `ubuntu-24.04` with Cosmoe's apt dependencies, cache the Cosmoe stage keyed on the tag, upload an artifact, and on `v*` tags attach it to the release only if none is attached yet.

## Headless testing (no VM needed)

The host needs `xorg-server-xvfb`, `openbox`, `xdotool` and ImageMagick.

```sh
Xvfb :99 -screen 0 1280x800x24 -nolisten tcp &   # keep running
DISPLAY=:99 openbox &                            # without a WM, Cosmoe windows get no focus or input
APP=./App APP_NAME=App LIBDIR=<stage>/usr/lib sh scripts/xtest.sh start c:600,400 k:ctrl+r shot:a
APP=/path/App-x86_64.AppImage APP_NAME=App sh scripts/xtest.sh start shot:b    # AppImage: no LIBDIR
```

`xtest.sh` keeps the app off the user's desktop: no `WAYLAND_DISPLAY`, `COSMOE_BACKEND=x11`, a throwaway HOME, and a fake `xdg-open` that logs to `$SCRATCH/xdg-open.log`. It also holds clicks for 150 ms. Crop screenshots to the window for READMEs: `import -window root -crop WxH+X+Y +repage`.

**Debugging:**

- **Backtraces:** Yama blocks `gdb -p`, so launch under gdb: `gdb -batch -ex run -ex "thread apply all bt 20" --args ./App`, reproduce, then `pkill -INT -x App`.
- **Library loading:** `LD_DEBUG=files` shows which libraries and add-ons load. `/proc/<pid>/maps` shows whether a library came from `/tmp/.mount_*` (bundled) or `/usr/lib` (host).
- **Timing:** `LD_DEBUG` and gdb slow startup and can hide timing problems, so confirm without them.
- **First run:** test both a **fresh HOME** and a reused one, and both the **mounted** and the extracted AppImage. cosmoe#4 only shows on a fresh HOME with the mounted image.

Not testable headlessly yet: the Wayland backend, and drag-and-drop from a Linux file manager (XDND). Use a desktop Linux VM (see virtualbox.md) or ask the user to try on their own session.
