# Haiku Human Interface Guidelines: the checklist

Every app we build, port or release follows the Haiku HIG, on Linux (Cosmoe) as well as on Renku/Haiku. Sources:

- HIG: https://www.haiku-os.org/docs/HIG/index.xml (one long DocBook page; chapter numbers below refer to it)
- Icon Guidelines: https://www.haiku-os.org/development/icon-guidelines/
- Overview of both: https://www.haiku-os.org/community/getting-involved/designing/

This file condenses the rules you can check. Read the HIG itself when a case isn't covered here. Where the HIG and the Renku/Haiku system apps disagree, follow what the system apps on the target actually do, and say so in the report.

**When porting** (porting.md), keep the original's layout, content and measured sizes, but use Haiku conventions for menus, wording, shortcuts, alerts, settings and controls. A Qt "Edit > Preferences…" becomes "Settings…" in the app menu. "Exit" becomes "Quit". "Yes/No" alerts get action labels. Title Case becomes sentence case. List each such change in the port's notes so the user can veto it.

## Conventions (ch. 3)

- Settings: a flattened `BMessage` in a `BFile`. One file goes in `B_USER_SETTINGS_DIRECTORY`. Several files go in a folder named after the app there.
- Never block a window's thread. Long work runs in its own thread. There is no busy cursor.
- Get every system path from `find_directory()`. Never hardcode `/boot/home/…`.
- Recent files: an "Open recent" submenu under File (`BRecentFilesList::NewFileListMenu()`).
- Live updates: lists and forms follow changes on disk (node monitoring) and in related fields.
- Images load through the Translation Kit. Depend only on translators that are installed by default.
- Prefer open, documented file formats. Use attributes and queries where they fit (index what you query).
- Deskbar replicant only for frequently updated information or frequently used features.
- Colours from `ui_color()`. System controls are sized with `GetPreferredSize()`/`ResizeToPreferred()` or layouts. Custom controls are sized from the font. Never redraw standard controls in your own look.

## Input (ch. 4)

Mouse: click selects or acts. Double-click opens. Secondary click opens a context menu. Drag selects or moves. Wheel scrolls. Wheel with Command zooms. Don't use modifier-drags, multi-clicks of non-primary buttons, or more than triple clicks.

Reserved shortcuts. Always use `B_COMMAND_KEY`, which is Alt on Haiku and Ctrl under Cosmoe. Never give these keys another meaning:

| Key | Action | Key | Action |
|---|---|---|---|
| Cmd+N | New | Cmd+Z | Undo |
| Cmd+O | Open… | Cmd+Shift+Z | Redo |
| Cmd+S | Save | Cmd+X / C / V | Cut / Copy / Paste |
| Cmd+Shift+S | Save as… | Cmd+A | Select all |
| Cmd+P | Print… | Cmd+F | Find… |
| Cmd+W | Close (window) | Cmd+G | Find again |
| Cmd+Q | Quit | Cmd+Option+F / Cmd+L | Replace / Replace and find |
| Cmd+, | Settings… | Cmd+B / I / U | Bold / Italic / Underline (text editors only) |

Shortcuts are only for common tasks. Command is the main modifier. Option means "a related variant". Tab and Shift+Tab move keyboard focus, so every control must be reachable that way. Make targets big, and give toolbar buttons labels where there's room.

## Drag and drop, clipboard, replicants (ch. 5)

- Accept drops where they make sense, Tracker files above all: `entry_ref`s in `"refs"`. Show a drag image, or a rectangle the size of the selection, and drop feedback such as an insertion line or a highlighted target.
- Clipboard text goes under `"text/plain"`, plus `"application/x-vnd.Be-text_run_array"` for styled text. Large data goes in a temp file put on the clipboard as `"refs"`.
- Replicants: a lightweight extra, at least 32×32, framed, the dragger allowed for in the layout. Not flashy.

## Text (ch. 6)

- **Sentence case** for everything: menus, buttons, labels, window titles. Capitalise only proper names (Tracker, Deskbar).
- **Ellipsis** is the single character `…` (`B_UTF8_ELLIPSIS`), never "...". Use it only when the item opens a window asking for more input. "Save" has none. "Save as…" does.
- No abbreviations or acronyms in menus or buttons. Avoid contractions.
- Error messages say what happened in everyday words and suggest a fix. No error codes or stack details unless there is a "Details" disclosure.
- Fonts: only `be_plain_font`, `be_bold_font` and `be_fixed_font`. Don't assume a font size; measure with `BFont::GetHeight()`. Bundle any other font (with the rights to do so).
- Command-line tools: GNU long options (`--option=value`), `-h`/`--help` reserved, help when required arguments are missing. Something destructive does nothing without an argument.

## Branding (ch. 7) and icons

- About window: name, version, author, copyright, an optional one-line licence. No system information, no tabs. Closes with Cmd+W. Use `BAboutWindow` where the headers have it. Renku's beta6 headers don't (renku.md), so build a small window with the same contents.
- Every app ships a vector (HVIF) icon. A poor icon is worse than the default one. Icon rules, from the Icon Guidelines:
  - Designed for 32×32 and still readable at 16×16. Only detail that is visible at 32×32. Use LOD to drop fine parts at small sizes.
  - Flat front view or BeOS isometric (floor edges at 2:1). Verticals stay vertical.
  - Main light from the top left, gradients follow it. Front faces lighter at the top, top faces lighter on the left, right sides darkest.
  - A black outline round the silhouette. Inner outlines rarely; thin parts get tinted outlines or none.
  - Saturated mixed hues, never pure RGB. Neutral greys. Shadows stay saturated and fall straight to the right, so leave room on the right edge.
  - Gloss only for metal or glass. Overlays (badges) are flat symbols that read at 16×16.
  - Culturally neutral.
  - `scripts/make-hvif-icon.py` encodes one (porting.md §5).

## Cursors (ch. 8)

Use system cursors. Make a custom one only when it clearly helps: at most 16×16, with an obvious hotspot.

## Menus (ch. 9)

- Short, accurate names, sentence case, `…` where input follows. A menu item that opens a window and that window share a name (without the `…`).
- Group items with separators. Avoid submenus; a submenu with 6 or more items becomes a top-level menu.
- On/off items get a checkmark. Multi-state settings list every state (radio-style marks).
- Standard menus, in this order where they exist:
  - **App menu** (the app's name, or the first menu): "About <App>…", "Settings…" (Cmd+,), separator, "Quit" (Cmd+Q). Many Haiku apps put these at the bottom of File; match the system apps on the target.
  - **File:** "New" (Cmd+N), "Open…" (Cmd+O), "Open recent" ▸, "Close" (Cmd+W), "Save" (Cmd+S), "Save as…" (Cmd+Shift+S), "Save all", "Revert", "Import from…", "Export to…" (only for lossy formats), "Page setup…", "Print…" (Cmd+P).
  - **Edit:** "Undo"/"Redo", dynamic where possible ("Undo typing"); separator; "Cut", "Copy", "Paste"; separator; "Select all". View changes such as zoom aren't undoable. No Copy or Paste in File.
  - **Search** (or in Edit): "Find…" (Cmd+F), "Find again" (Cmd+G).
  - **Help:** "User guide…" or a similar name, opened in a window or the browser, never in a `BAlert`; "<App> website".

## Windows (ch. 10)

- Titles: the main window includes the app's name; documents show their document name; new ones are "Untitled", "Untitled 2", and so on. A titled window is never blank.
- Initial size: the smallest that shows every control uncrowded. Make it the minimum with `SetSizeLimits()`. Document windows fit their document where possible. Don't block resizing without a reason.
- Placement: centred or a little above centre (`CenterOnScreen()`). Each new document window is offset from the last by the tab height. **Remember the size and position** across runs.
- Utility windows: no zoom, no minimise. Document and main windows can be minimised.
- No `B_ACCEPTS_FIRST_CLICK` except for small utilities and monitors.
- Modeless by default. Modal only where skipping the window would risk losing data.

## Alerts, find, settings, file panels (ch. 11)

- **Alerts** are a last resort; handle what you can silently. Don't ask what the program can decide. Never "Are you sure you want to quit?": offer to save unsaved documents, then quit. Confirm only actions that can't be undone; moving to Trash can be. Information alerts have "OK". Questions have action labels ("Don't save", "Cancel", "Save"), never Yes/No. The default button is the safest common choice, and the rightmost button is the default.
- **Find windows:** case-insensitive by default with a case-sensitive option. Regular expressions only in tools for programmers.
- **Settings windows:** good defaults. Apply changes live where possible, with "Revert" and "Defaults" buttons. Only settings that matter, in plain words. Dates use the system format (`BDateFormat`).
- **File panels:** `BFilePanel`. Start in the last folder used (Home if it's gone). Filter to supported types but keep files with no MIME type visible. Suggest a filename when saving a new document. The panel title names the task ("Open", "Save as", "Export as").

## Controls (ch. 12)

- **Buttons:** preferred size, padding around them, never blank, never used as labels, one action per button. The default button (`MakeDefault`) is the one Enter triggers.
- **Checkboxes:** their label says what "on" does. Not for choosing one of several options; use radio buttons for that.
- **Radio buttons:** always a group with a default. At most 5–6; use a menu field or list beyond that.
- **Boxes (`BBox`):** labelled, used when there are many controls. Not round a single control, not nested.
- **Sliders:** both ends labelled. Tick marks for steps. The larger value is right or up. Never used as a progress bar.
- **Labels:** next to their control; use the control's built-in label where it has one. Long static text goes in a read-only `BTextView`.
- **Text controls:** validate input and filter characters, size the field for typical input, support the clipboard. Don't limit length without a reason. Multi-line text goes in a `BTextView` with undo.
- **Lists:** sorted, with "Select all" when several items can be selected. Not for a couple of items or for hundreds (add search).
- **Tabs:** for complex dialogs. No nesting, no OK/Cancel inside a tab, no tabs for choosing a mode, no scrolling tabs.
- **Scroll bars:** update range and step when the view resizes. Never scroll a form; never nest `BScrollView`s.
- **Menu fields** instead of radio buttons where space is short. **Pop-up menus** for context menus on the secondary button, never from a button press.
- **Progress bars:** labelled, for anything slow. **Toolbars:** only for common functions, standard icons where they exist, no scrolling, not crowded.

## Checking an app against the HIG

Run through this list during the UI pass of a port, at onboarding (onboard.md §1) and before a release (release-test.md):

1. Menus: names, order, `…`, shortcuts, sentence case (`hey App get Window 0`, and screenshots of each menu).
2. `grep -rn '\.\.\."' src/` finds three-dot ellipses. Search the source for Title Case strings, "Yes"/"No" alerts, "Preferences", "Exit" and "Are you sure".
3. Keyboard: every control reachable with Tab; reserved shortcuts do what the table says.
4. Windows: title, minimum size, centred on first run, size and position remembered after a restart.
5. Settings: stored under `B_USER_SETTINGS_DIRECTORY`; changes apply live where the app allows.
6. About window contents and the icon at 16×16 and 32×32.
7. Larger system font (Appearance → 15 pt): nothing clipped or overlapping.

Report each item that deviates and why (the original app needs it, a system limitation, or the user asked for it), rather than silently skipping it.
