# Porting an app to the native Haiku API (from Qt, GTK, SDL, …)

How to turn an app that runs on Haiku through another toolkit (or not at all)
into a BeOS-style app. Worked example: EasyPaint, a Qt 5 paint program ported
in Oct 2026 (github.com/idumych/EasyPaint, branch `haiku-native`; a GitHub
fork of the source it came from, with the port on top of upstream history).

## 1. Get reference screenshots of the original — before writing any UI

The native version must look and feel like the original, at the original's
dimensions. Write that down from pictures, not from memory or the source
code: in EasyPaint the first native build had a tool box half again too
wide, 22 px icons on flat buttons and a labelled pop-up menu, where the Qt
version had a 71 px tool box, 28 px bevelled buttons with 16 px icons and a
compact spin field. The user caught it from a screenshot.

1. **Collect** every screenshot of the original you can find, and keep the
   URLs:
   - the project's README (GitHub/GitLab), and the README of any fork that
     packaged it for Haiku;
   - the package's own readme on SourceForge or HaikuPorts (the SourceForge
     `readme.md` for EasyPaint linked a screenshot on postimg.cc);
   - HaikuDepot (depot.haiku-os.org), forum posts (forum.desktoponfire.com,
     discuss.haiku-os.org), the BeBits/Haikuware mirrors for old apps;
   - **ask the user** if they have one: they may post the one they care about.
   Put them in the scratchpad (`<scratch>/ref/`), not in the repo, unless the
   licence allows republishing them.
2. **If there are none, make them:** install the original in the test VM
   (`pkgman install` the old .hpkg, or build it), open a typical document and
   screenshot the window, its dialogs and its menus.
3. **Measure** with PIL rather than by eye: scan a row or column for border
   pixels and write the numbers down. Example, from the EasyPaint reference:

   ```python
   im = Image.open("ref.png").convert("RGB")
   # dark button borders along one row -> left/right edges of each button
   print([x for x in range(0, 80) if sum(im.getpixel((x, 69))) < 450])
   # runs of non-background pixels -> palette swatch size and pitch
   ```

   Record: panel widths, button size and gap, icon size, insets, swatch size
   and pitch, which separators exist, label texts and number formats in the
   status bar ("671 x 391", "8,290"), and which menus exist.
4. **Compare after every UI build:** screenshot the native window, crop the
   same region of both, paste them side by side at 3× (`Image.NEAREST`) and
   rerun the same pixel scans. Aim for ±1–2 px. Remember the window border:
   a Haiku window's content starts 5 px inside its frame, and a crop taken at
   `frame.left - 6` is 1 px off one taken at the border.
5. Differences you keep on purpose (one window per document instead of tabs,
   Haiku menu names, Alt shortcuts) go in the README's "What's different"
   section.

## 2. Read the whole original first

List every menu item, tool, dialog, setting and command-line option, and
map each to its native counterpart. Note the original's bugs as you go and
decide per bug: keep (fidelity) or fix (say so in the README). EasyPaint's
fixes: binarization inverted, blur intensity a no-op, all-zero custom
kernel, recursive flood fill overflowing the stack, zoom that rescaled the
pixels.

## 3. Structure

- **Portable core** (`src/core/`, no Haiku headers) for anything that is
  plain computation: pixel effects, fills, parsers, sync logic. Give it
  `make test` on the host. Keep pixel buffers as `uint32 0xAARRGGBB`, which
  is B_RGBA32's memory layout on little-endian machines.
- **One window per document** with its own menu bar; the BApplication keeps
  shared state (current tool, colours) and broadcasts a "state changed"
  message to the windows. `B_SINGLE_LAUNCH` so Tracker and the command line
  open documents in the running app (`RefsReceived`, `ArgvReceived` with the
  `cwd` field).
- **Dialogs are asynchronous windows** that send a reply message to a
  `BMessenger`; `B_MODAL_SUBSET_WINDOW_FEEL` + `AddToSubset(parent)` when they
  must block their document window. Use a synchronous `BAlert::Go()` only for
  the save-changes question in `QuitRequested()`.
- **When a window changes shared state and acts on it at once** (Paste
  switching to the selection tool), update the state locally first and then
  tell the app. Otherwise the app's broadcast arrives after the action and
  undoes it (the "tool changed" handler finished the selection that Paste had
  just made).
- Files through the Translation Kit (`BTranslationUtils::GetBitmap`, a
  `BBitmapStream` + `BTranslatorRoster::Translate` to the translator whose
  output MIME type matches), and set `BNodeInfo::SetType`. Pick the format
  from the existing file's type first, then the extension, so extensionless
  Haiku files keep their format.
- Clipboard images as ShowImage does: an archived BBitmap under
  `"image/bitmap"`; also accept raw `image/*` data.
- Strings through `B_TRANSLATE` (link `-llocalestub` on Haiku) even without
  catalogs yet.

## 4. API traps met while porting

- **`BSpinner` / `BDecimalSpinner` are private** (`headers/private`): not
  in the public headers, so the type-check fails. Use a `BTextControl` that
  allows only digits (`TextView()->DisallowChar` for everything else) plus,
  if the original had a spin box, a small `BView` stepper drawn with
  `be_control_look->DrawButtonFrame/DrawButtonBackground`.
- **Views added to a layout that has no owner view never become child
  views.** `new BGridLayout` → `AddView(button…)` → add the grid to a group
  later: the space is reserved but the buttons don't exist (`hey … get View
  N of View toolbox` doesn't find them). Create the grid inside its parent
  first: `BLayoutBuilder::Group<>(this).AddGrid(6, 6).GetLayout(&grid)`, then
  add views.
- **A `BTextControl` sends its modification message when the program calls
  `SetText()`**, and the message arrives later. A boolean "updating" guard
  around `SetText` therefore does nothing; two linked fields (width/height
  with "keep aspect") ping-pong. Act only when the value differs from the one
  you stored.
- **`BButton` as a toolbar button:** `SetIcon(bitmap)`, `SetBehavior(
  B_TOGGLE_BEHAVIOR)`, `SetExplicitSize(BSize(n - 1, n - 1))` (BSize is the
  width minus one). Flat (`SetFlat(true)`) only if the original's buttons
  were flat.
- `BCursor(const BBitmap*, BPoint hotspot)` works for tool pointers;
  `BCursor(B_CURSOR_ID_…)` for system ones. A cursor can be deleted after
  `SetViewCursor`.
- **A `BBitmap` needs a `BApplication`**: a throwaway test program that makes
  one without an app hangs forever.
- **`BTextView` inserts Tab characters**; Tab doesn't move focus out of it.
- **Synchronous alerts block scripting:** with unsaved changes,
  `hey <App> quit` waits on the save prompt forever. Test scripts kill the
  team instead.
- The renku.md notes still apply: no `BAboutWindow` in beta6 headers (use a
  `BAlert`).

## 5. A vector icon without Icon-O-Matic

`scripts/make-hvif-icon.py` encodes HVIF directly (styles, closed polygon
paths, shapes; solid colours and linear gradients) and writes an SVG preview
from the same geometry. Copy it into the app's `tools/`, change `build()`,
and paste the generated `resource vector_icon { … }` into the .rdef. Format
facts that matter (Haiku `src/libs/icon/flat_icon/FlatIconFormat.h`): magic
`ncif`, style types solid = 1, **gradient = 2**, solid-no-alpha = 3;
gradients span −64…64 along x before their 6-float24 matrix (sx, shy, shx,
sy, tx, ty); path flags closed = 1<<1, no-curves = 1<<3; shape type 10.

Check the icon on Haiku, not only in the SVG: `listattr` should show
`BEOS:ICON`, Tracker should draw it (a generic "blocks" icon means the data
didn't parse), and `BIconUtils::GetVectorIcon` in a test program (with a
`BApplication`) should return `B_OK`.

## 6. Exercising the UI when clicks don't work

When the VM's pointer is PS/2 (absolute clicks fail, see virtualbox.md),
deliver mouse messages straight to a view with `hey`; they go through
`BWindow::DispatchMessage` into the view's `MouseDown/Moved/Up`, so the app
code under test is the real one:

```sh
C='View canvas of View scroller of Window "Untitled"'
hey MyApp let $C do _MDN with be:view_where="BPoint(20,20)" and buttons="int32(1)" and clicks="int32(1)"
hey MyApp let $C do _MMV with be:view_where="BPoint(150,120)" and buttons="int32(1)"
hey MyApp let $C do _MUP with be:view_where="BPoint(150,120)" and buttons="int32(0)"
hey MyApp let Window "Untitled" do COPY          # any message: 'efct', B_COPY, …
hey MyApp tool with tool="int32(5)"              # to the app itself
hey MyApp set Frame of Window 0 to "BRect(150,110,646,512)"
hey MyApp set Active of Window "Text" to true
```

`scripts/hey-ui.sh` has these as shell functions (`down`, `move`, `up`,
`drag`, `click`) to source in the guest. Name views (`BView("canvas", …)`)
so specifiers can find them, and address windows by title: `Window 0`
changes as windows open and close. Typing still goes through
`VBoxManage keyboardputstring`. Say in reports that input was scripted.

## 7. Screenshots for the README

Take them after the UI matches the reference (§1), at the platform's own
resolution:

1. Close everything else: minimize Terminal (`hey Terminal set Minimize of
   Window 0 to true`), close Tracker windows you opened (`hey Tracker let
   Window "<title>" do _QRQ`), and close crash dialogs from test programs
   with `hey debug_server let Window "Crashed program" do _QRQ` (repeat while
   `hey debug_server count Window` is above 0).
2. Draw or open a document that shows the app at work, through the app's own
   tools (§6).
3. Size the window to fit it (`set Frame`), move the pointer off the window
   (a relative `putMouseEvent`, virtualbox.md), and screenshot.
4. Crop to the window: `(frame.left - 6, frame.top - 29, frame.right + 7,
   frame.bottom + 8)` includes the border and the yellow tab. Paint any other
   app showing inside the crop (the Deskbar corner) with the desktop colour.
5. Check each image before committing, and save them as
   `docs/screenshots/<platform>-<what>.png` (PIL `optimize=True`), the
   layout release.md expects. (EasyPaint predates that and uses
   `screenshots/`.)
