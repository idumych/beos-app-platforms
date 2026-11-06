# Theming Renku OS and Haiku: decorators, control looks, colours, fonts

Learned building [Gonx](https://github.com/idumych/gonx), a full look (window decorator, control
look, colours, fonts) installed by a zip with `install.sh`, and
[Power Theme](https://github.com/idumych/power-theme), a theme manager with several looks
(Windows ME, ZETA-style Smoke, Flat, Gonx), Theme Manager themes and freedesktop icon themes,
shipped as an `.hpkg` that builds its add-ons on the user's system. A look has four parts, and
each is switched separately:

| Part | What it is | Loaded by | Switch with |
|---|---|---|---|
| Window decorator | `add-ons/decorators/<Name>`, entry `instantiate_decor_addon` | app_server | `setdecor <Name>`, Appearance |
| Control look | `add-ons/control_look/<Name>`, entry `instantiate_control_look` | libbe, in every app | `BPrivate::set_control_look(path)`, Appearance |
| Colours | `ui_color` / `set_ui_colors`; desktop colour `BScreen().SetDesktopColor(c, true)` | app_server | a small theme tool |
| Fonts | plain, bold, fixed via `_set_system_font_`; menu via `set_menu_info` | app_server | the same tool |

Hokku/Cosmoe has no app_server decorators or control-look add-ons: a look is Renku/Haiku only.

## Decorator

- It is a **private-ABI add-on loaded into app_server**: compiled against app_server's private
  headers and linked against the `app_server` binary itself
  (`$(CXX) -shared … -lbe /boot/system/servers/app_server`). A crash in it takes the desktop
  down. Recovery: hold Space at boot, *Select safe mode options*, *Disable user add-ons*. Put
  that in every install script and README.
- Include app_server's directories with **`-iquote`, not `-I`**: its `Window.h`, `View.h` etc.
  otherwise shadow the public kit headers for system includes.
- Derive from **`Decorator`, not `TabDecorator`**, if the tab geometry is your own (a title bar
  across the window): `TabDecorator` re-runs its private `_LayoutTabItems` and moves your
  buttons back.
- For a **BeOS-style sliding tab, derive from `TabDecorator`** (sliding, stacking and resizing
  come free) and adjust around it (Power Theme's `src/smoke`):
  - Tab height: override `_DoTabLayout()`, call the base, then move each `tabRect.top` (and
    `closeRect`/`zoomRect` by the same delta), rebuild `fTitleBarRect` and call
    `_CalculateTabsRegion()`. Later layouts (`_ResizeBy`, `_SetTabLocation`, `_SetFocus`) only
    move tabs sideways or place buttons from the tab's top, so the height sticks.
  - Button rects: override `_GetButtonSizeAndOffset()` with sizes that don't depend on the
    `tabRect` passed in (it is the pre-adjustment one).
  - Border width: override `_DoLayout()` entirely (it's short) to set `fBorderWidth`,
    `fResizeKnobSize` (the footprint's content-corner knob is `fResizeKnobSize - fBorderWidth`)
    and the border rects, then call `_DoTabLayout()`.
  - A tab that flows into the frame: `tabRect.bottom` is the frame's top row, so the rows below
    it belong to the frame. Paint that part of the tab from `_DrawFrame()` too, or a partial
    redraw of the frame paints frame lines across the tab.
  - `GetComponentColors` isn't virtual in `TabDecorator` (only in `DefaultDecorator`).
  - **Never `ConstrainClippingRegion()`** in a decorator to redraw under a button: it replaces
    the window's own clipping, and `NULL` lets you paint over other windows. Refill the button
    rect with the same gradient instead.
- Colours derived from the tab colour: darken by **scaling** (`colour × (brightness − d) /
  brightness`), not by subtracting `d` per channel. On a grey both give the same, but
  subtracting turns orange (#FF6A13) into a saturated red edge instead of a dark one.
- **Every decorator with a title bar across the window must also draw a BeOS-style tab**, so that
  Power Theme's *BeOS-style tabs* option (`powertheme --beos-tabs=on`) works with it. A decorator
  that already draws a narrow tab, as Tidy's does, needs nothing. See § BeOS-style tabs.
- `_GetFootprint` is the region you draw. `Window::_UpdateContentRegion` subtracts it from the
  content, so a footprint that bites into the content's corners gives rounded inner corners.
  Anything you paint outside it (a shadow, a flap) is clipped or left behind as garbage.
- A decorator can't read or blend with what is under the window. Soft shadows and anti-aliased
  outer edges are painted over a fixed colour (the desktop colour of the theme); over another
  window they show as a thin dark edge. Say so in the README.
- Don't reach into `Desktop` internals for things like the desktop colour: that's where the ABI
  differs between builds. A constant is safer.
- app_server bug (Renku and Haiku): `Window::ReloadDecor()` doesn't reset
  `fContentRegionValid`, so windows already open keep the old decorator's content region (square
  corners, gaps) until resized or reopened. A reboot clears it. Not an add-on bug; report to
  RenkuOS/Source only with the user's go-ahead.

## BeOS-style tabs

Part of porting any full-width title bar, not an extra: a port isn't finished until the option
works with it. Reactionary, Expose and Platinum in Power Theme are the examples to copy.

- **The setting:** the add-on's constructor checks that `PowerTheme/beos tabs` exists in
  `B_USER_SETTINGS_DIRECTORY` and passes the answer to each decorator it allocates. Add-ons read it
  as they load, and Power Theme reloads the decorator when it changes.
- **Register it:** add the decorator's file name to `draws_beos_tabs()` in Power Theme's
  `src/themes/Theme.cpp`. Until then the option is off for that theme's window, and the command
  still reports it as on, with no effect.
- **The frame:** with tabs on, the frame gets a real top edge, as a window with no title has. Its
  top corners are square where a tab reaches them.
- **The tab:** it sits on the frame, overlapping its top edge so they join. A lone tab is as wide
  as its title and buttons, and `_TabWidth()` must leave room for anything the look shows beside the
  title, such as stripes. A stack's tabs share the window's width.
- **Buttons:** close on the left, zoom on the right, no minimize. Lay these out from the tab rather
  than the window, because a bar's button order often differs.
- **Sliding:** `_SetTabLocation()` clamps the location to the window, and `_SetSettings()` restores
  it, keeping a bar's location for when it becomes a tab again. Re-clamp on every layout, so that a
  slid tab stays on a window that has been narrowed.
- **Keep the look:** the tab keeps the bar's shading, corners and buttons. Reuse the code that
  draws the bar, and take away what only makes sense across a window, such as a recess along its
  bottom.

Test all of it, in each mode the theme has, reopening windows first (see the `ReloadDecor` bug
above):

- on and off, with the status line and a screenshot of each;
- shift-drag the tab from its title (start on the text: a narrow tab has little room between its
  buttons, and a drag that starts on zoom zooms the window);
- narrow a window with a slid tab, and check the tab stays on it;
- click close and zoom on the tab;
- move a window, and check the tab goes with it;
- stack two windows if you can. Synthesised keys didn't start a stack in a VM, so if you can't, say
  it's untested.

## Control look

- Subclass the private **`BPrivate::HaikuControlLook`** (libbe) and override only what you
  change; export `extern "C" BControlLook* instantiate_control_look(image_id)`. Because it
  subclasses a private class, a control look is tied to the system build too, like a decorator
  (its vtable must match libbe's): build it on the target with the decorators.
- A `BMenuField`'s pop-up marker room is on the right (`kPopUpIndicatorWidth`, 13px); text
  starts after the left item margin. A marker drawn on the left overlaps the label unless you
  also swap the margins (see below).
- **Keep Haiku's inset contracts** or labels and layouts shift: `DrawButtonFrame` insets the rect
  by 2px (5px for the default button), `DrawButtonBackground` by 1px, and callers lay out the
  label in what's left. A different border thickness must still consume the same inset.
- Controls split into segments (spinner up/down, segmented buttons) pass `borders` without some
  sides: extend the shape past the open sides before rounding, or every segment gets corners.
- Wrap every menu drawing override in `view->PushState()` / `PopState()`. Without it a changed
  high colour leaks into the label, and highlighted menu items draw their text invisibly.
- `BButton` centres its label in the rect you return and opens its pop-up only in its right-hand
  `_PopUpRect`: a pop-up button's arrow can't move to the left. A `BMenuField` can: swap the
  item margins (`BPrivate::MenuPrivate::Get/SetItemMargins`; `BMenuItem` reads them at draw time
  via `ContentLocation`).
- A control look can't change a control's preferred size. To draw a shorter button than
  `BButton` asks for, shrink the rect inside `DrawButtonFrame` (Gonx's `_FitButtonHeight`:
  only when both top and bottom borders are drawn, and only within the automatic height, so
  buttons a layout stretched on purpose stay as laid out). Text height comes from the fonts
  (below), so set fonts first and then measure.
- Small outlined arrows look cleaner rasterized pixel by pixel than with `FillTriangle` +
  `StrokeTriangle` at 5–9px.
- `BStringView` status lines under `B_AUTO_UPDATE_SIZE_LIMITS` widen the window to fit a long
  message, even with an explicit min width of 0 and truncation: keep status messages short and
  put the long text in a log view.
- A demo app with every control in one window (buttons default/normal/disabled, check boxes,
  radio buttons, menu fields and pop-ups, slider, scroll bars, tabs, text control, list, status
  bar, box) is the fastest way to compare against reference art.

## Colours and fonts (the theme tool)

- `ui_color()` returns built-in defaults **without a `BApplication`**: a command-line tool must
  create one before reading or saving colours, or it saves the defaults as "previous".
- Fonts: `_set_system_font_("plain"|"bold"|"fixed", family, style, size)` (private, from
  `<private/interface/…>` / libbe); the menu font is **only** set via `get_menu_info` /
  `set_menu_info`.
- Save everything you change (decorator name, control look path, every colour, desktop colour,
  fonts) under `~/config/settings/<Name>/previous` on `apply`, and offer `revert` and `status`.
  Upgrade an older saved state that lacks newer fields instead of overwriting it.
- Look for the control look in the user non-packaged, user and system add-on directories.
- Running apps keep the old control look and fonts until restarted; say so after `apply`.

## Building one look for many system builds

- The decorator and control look interfaces are **identical from Haiku R1/beta6 to current
  Renku** (Oct 2026). The private headers differ only in `ServerBitmap.h` and
  `ClientMemoryAllocator.h` (`AreaOffset` uint32 vs size_t, unused by a decorator).
- So: bundle the exact private headers the add-ons need (Gonx: 39 app_server/libbe headers plus
  15 FreeType headers, with a NOTICE for MIT/FTL) in the source, and **build on the target**.
  `haiku_devel` + `gcc` + `rc`/`xres` are enough; no source tree, no make.
- **Ship the add-ons as source, not binaries.** An `.hpkg` with prebuilt private-ABI add-ons
  must pin the exact `haiku` version (`requires haiku == <ver>`) and blocks or breaks at the next
  update. Power Theme's package instead holds the app, the themes, the add-ons' sources and a
  build script (`src/themes/build-decorators.sh`); its "Build add-ons…" window runs the script,
  shows `STEP <percent> <what>` lines in a progress bar and the rest in a log, and installs into
  `~/config/non-packaged/add-ons`. The package itself then needs only `haiku >= <oldest>` and
  works on every build. (Gonx's older way: a zip whose `install.sh` builds when a compiler is
  present, else uses prebuilt files with a `BUILT_FOR` warning.)
- **Headers for the running build**, when the bundled ones are from another:
  - The revision is in the haiku package's name: `/boot/system/packages/haiku-r1~beta6_hrev60072_339-1-x86_64.hpkg`
    is `hrev60072+339` (`git describe` style: 339 commits past the tag).
  - Renku: tags and commits on `github.com/RenkuOS/Source`. Haiku: the GitHub mirror has no
    `hrev` tags; take the tag's commit from `git ls-remote https://review.haiku-os.org/haiku
    refs/tags/hrevN` (Gerrit doesn't support `--filter` or `--shallow-exclude`), and fetch
    commits from `github.com/haiku/haiku`.
  - Every commit on Haiku's `master` has its own hrev tag, so `hrevN+M` is on a **release
    branch**: try the one the version names (`r1~beta6` → `r1beta6`) before `master`, or you
    find a different commit M past the tag on master.
  - `git fetch --filter=tree:0 origin <branch>` (commits only: ~23 MB for Haiku, seconds), then
    binary-search the `--first-parent` line for the commit where `git rev-list --count C ^tag`
    equals M, then `git checkout <commit> -- <the header paths>` fetches just those files.
  - Cache them (`~/config/cache` is **read-only on Renku**; use `~/config/settings/<App>`), and
    stop if they can't be fetched: add-ons built against another build's headers take
    app_server down later, when a theme is applied, not at build time.
  - Haiku R1/beta6 has no git by default: the build offers `pkgman install gcc haiku_devel git`
    for what's missing.
- **Never overwrite a loaded add-on in place**: apps that have it mapped crash. Copy to
  `<file>.new` and `mv` over it.
- After switching, check app_server survived: its team id (`ps | grep app_server`) must be
  unchanged. A rebuilt decorator that is in use only loads after `setdecor Default; setdecor
  <Name>`: do that, check the team id, and set the file aside (`<Name>.failed`) if app_server
  restarted.

## Cross-building on Linux

Use the cross g++ from a configured Renku source tree (`generated/cross-tools-x86_64`) against a
sysroot copied from one running Renku VM (`tools/sync-sysroot.sh <ssh-host>` in Gonx):

- `/boot/system/develop/{lib,headers}` (install `freetype_devel` there first: app_server's font
  headers include FreeType's), plus `libstdc++.so*` and `libgcc_s.so*` from `/boot/system/lib`,
  which are not under `develop/`.
- `/boot/system/servers/app_server`, to link the decorator against.
- The `haiku` package version, written to `build/BUILT_FOR`.

`rc` runs over SSH on the VM; `xres` can come from the source tree's generated build tools.

## Deploying to a test VM

- `pkgman install` of a package with the **same version** as the installed one is a silent
  no-op. Uninstall first, then install, then compare `md5sum` on the VM with the local build.
  Otherwise screenshots show the old build.
- Close Terminal with `kill`, not `hey Terminal quit`: its "really quit?" prompt blocks `hey`.
  A reboot can stall on the same prompt; click *Kill application*.
- Address windows by title in `hey`, not `Window 0`: Tracker's window 0 is the Desktop, and
  resizing it breaks the desktop until Tracker restarts.
- Haiku's `ps` prints more columns after the path: match with `awk '$1 ~ /PowerTheme$/'`, not
  `grep 'PowerTheme$'`. There is no `pkill`; kill by the team id from `ps`. `hey <App> quit` can
  hang on a confirmation (Screen preferences): run it under `timeout` or `kill` instead.
- Screenshots after `--restart-tracker`: Tracker reopens the windows it had (home, disks), which
  can show the test VM's private folder names. Close them with `hey Tracker quit Window <title>`
  and open a neutral folder (`/boot/system/apps`).
- A single-window app keeps its old binary running: after installing a new build, kill the
  running instance, or a new launch only activates the old window. Never `scp` over a running
  app's binary (it crashes); copy to `.new` and `mv`.
- Matching reference art: upscale low-resolution mockups (`waifu2x-ncnn-vulkan`) to read
  detail, but measure sizes on the originals. Crop the same region of the VM screenshot at the
  same scale and compare side by side after every change.

## Copyright

Mockups, screenshots and videos of old systems (BeOS, Dano, Zeta) are fine as visual references.
Don't use leaked BeOS/Dano/Zeta source code, even "abandonware" archives: it's copyrighted and
taints Haiku-family work. The same goes for **binaries and artwork**: don't extract, convert or
ship ZETA's decorators, bitmaps or theme files, even when the user calls them abandonware.
Recreate the look instead: run the original in a VM (beos.md § ZETA), screenshot it, measure
pixel by pixel (frame lines, gradient end points, glyph masks), derive colours from the system
colours as offsets, and write a new add-on (Power Theme's Smoke). Keep the screenshots out of the
repository. Credit the original look by name and say nothing of it is included. Credit artwork you copy (Gonx copies Momo's IceWM glyphs pixel for
pixel, credited in the README).
