# Theming Renku OS and Haiku: decorators, control looks, colours, fonts

Learned building [Gonx](https://github.com/idumych/gonx), a full look (window decorator, control
look, colours, fonts) installed by a zip with `install.sh`. A look has four parts, and each is
switched separately:

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
- Derive from **`Decorator`, not `TabDecorator`**, if the tab geometry is your own:
  `TabDecorator` re-runs its private `_LayoutTabItems` and moves your buttons back.
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

## Control look

- Subclass the private **`BPrivate::HaikuControlLook`** (libbe) and override only what you
  change; export `extern "C" BControlLook* instantiate_control_look(image_id)`.
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
  `haiku_devel` + `gcc` + `make` are enough; no source tree.
- Ship a zip, not an `.hpkg`: an `.hpkg` of a private-ABI add-on must pin the exact `haiku`
  version (`requires haiku == <ver>`) and breaks at the next update. The zip's `install.sh`
  builds when a compiler is present, else uses prebuilt files and warns if `prebuilt/BUILT_FOR`
  differs from the running `haiku` version. It installs to `~/config/non-packaged` (no package
  database), refuses if the package version is installed, and `uninstall.sh` reverts first.
- **Never overwrite a loaded add-on in place**: apps that have it mapped crash. Copy to
  `<file>.new` and `mv` over it.
- After switching, check app_server survived: its team id (`ps | grep app_server`) must be
  unchanged.

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
- Matching reference art: upscale low-resolution mockups (`waifu2x-ncnn-vulkan`) to read
  detail, but measure sizes on the originals. Crop the same region of the VM screenshot at the
  same scale and compare side by side after every change.

## Copyright

Mockups, screenshots and videos of old systems (BeOS, Dano, Zeta) are fine as visual references.
Don't use leaked BeOS/Dano/Zeta source code, even "abandonware" archives: it's copyrighted and
taints Haiku-family work. Credit artwork you copy (Gonx copies Momo's IceWM glyphs pixel for
pixel, credited in the README).
