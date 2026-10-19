# Worked example: Folio

Folio (github.com/idumych/folio) is a OneNote-style notebook app: Markdown pages, `[[wiki links]]` that are rewritten when pages move, tags, to-dos and attachments. It ships on all three platforms from one tree. Use its files as templates for a new app:

| Piece | Folio file |
|---|---|
| Platform-detecting Makefile (Haiku, V\OS via pkg-config or headers, Cosmoe, `make deb`/`hpkg`) | `Makefile` |
| Haiku/Renku package | `packaging/haiku/build-hpkg.sh`, `PackageInfo.in` |
| VitruvianOS package (attributes tarball + postinst) | `packaging/build-deb.sh`, `packaging/debian/{postinst,changelog,copyright}` |
| VitruvianOS link-time SDK | `tools/vos-sdk/make-sdk.sh`, `vos-0.6.2-linkonly.patch` |
| AppImage | `packaging/appimage/{build-appimage.sh,AppRun,fonts.conf,folio.desktop,folio.svg,folio.png}` |
| CI | `.github/workflows/test.yml` (unit tests), `appimage.yml` (AppImage; release attach) |
| Type-check against real Haiku headers on Linux | `tools/typecheck/haiku-check.sh` |
| Cosmoe define and code | `FOLIO_COSMOE` in `Vault.cpp` (`_Watch`, `FindNumber`, `_EventEntry`), `Widgets.cpp` (`OpenEntry`/`OpenURL`), `NoteView.cpp` (faces), `Constants.h` |

## Folio's release checklist

- **Version** lives in: `Folio.rdef` (`middle`/`minor`), `packaging/build-deb.sh`, `packaging/haiku/build-hpkg.sh` and `packaging/appimage/build-appimage.sh` (`VERSION=`), `packaging/debian/changelog`, the file names in `README.md`, and a new `packaging/release-notes-<v>.md`.
- **Host checks:** `make test` (38+ checks), `sh tools/typecheck/haiku-check.sh`, then `. .vos-sdk/sdk/env.sh && make` and `make deb`.
- **hpkg:** built over `ssh folio-haiku` (the Haiku beta6 VM).
- **Release assets:** `folio_<v>-1_amd64.deb`, `folio-<v>-1-x86_64.hpkg`, `Folio-<v>-x86_64.AppImage`, `SHA256SUMS`.

## Folio's core feature test (run it on every platform)

1. A fresh launch creates `~/Notebooks/Welcome/Getting Started/` with three pages.
2. Rename "Start Here" through the app (command key + R). Then `Links and Renaming.md` contains `[[New]]`, `[[New#Links]]` and `[[New|the welcome page]]`.
3. With Folio running, `mv` that page in a terminal. All three links follow.
4. `mv` a **section folder**, then a page inside it. The second rename is what catches stale path watches on Cosmoe.
5. Ctrl/Alt-click the red `[[My First Idea]]`: the page is created. Tick a `[ ]`: `FOLIO:open_tasks` drops.
6. Attach an image with command key + I: a thumbnail appears (on Cosmoe, also on a fresh-HOME first run).
7. Move to Trash: check the platform's Trash location (see the cheat sheet).
8. The log stays empty.

Check with `grep -o '\[\[[^]]*\]\]' *.md` in the notebook folder.

## Where Folio has been verified (Oct 2026)

- **Haiku R1/beta6** (hrev59866): full pass. This is the hpkg build machine.
- **Renku OS** nightly build00055: full pass with the beta6-built hpkg.
- **VitruvianOS 0.6.2:** full pass, including Tracker drag-and-drop and restoring from the Trash.
- **Linux** (CachyOS, X11 under Xvfb + Openbox): full pass with the CI AppImage. Not tested: Wayland, XDND.
