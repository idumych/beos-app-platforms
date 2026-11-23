# Worked example: Folio

Folio (github.com/idumych/folio) is a OneNote-style notebook app: Markdown pages, `[[wiki links]]` that are rewritten when pages move, tags, to-dos and attachments. It ships on all three platforms from one tree and was onboarded with `templates/` for 0.1.3, so it shows what an onboarded app looks like:

| Piece | Folio file |
|---|---|
| App settings for the pipeline | `haiku-app.env` (feature checks `welcome rename-links external-move`, three `EVIDENCE_n` rules) |
| Feature test | `release/test-plan.md`: rename a page in the app, then `mv` it in a shell while Folio runs, and check the links on disk; `{p}` in the names keeps each platform's evidence distinct |
| Platform-detecting Makefile | `Makefile` (Haiku; V\OS via `pkg-config vos` or `/system/develop/headers`; Cosmoe via `COSMOE_ROOT`) |
| Packaging, CI, type-check, V\OS SDK | template copies: `packaging/`, `.github/workflows/`, `tools/` |
| Cosmoe-specific code | `FOLIO_COSMOE` in `Vault.cpp` (`_Watch`, `FindNumber`, `_EventEntry`), `Widgets.cpp` (`OpenEntry`/`OpenURL`), `NoteView.cpp` (faces), `Constants.h` |

Its portable core (`MarkdownScan`, `LinkGraph`) has no Haiku headers, so `make test` runs anywhere, and its node-monitor handling accepts Haiku's, V\OS's and Cosmoe's message layouts, with a path fallback.

## Where Folio has been verified (Oct 2026)

- **Haiku R1/beta6** (hrev59866): full pass (0.1.2 by hand; 0.1.3 through the release gate).
- **Renku OS** nightly build00055: full pass with the beta6-built hpkg (0.1.2).
- **VitruvianOS 0.6.2** amd64: full pass, including Tracker drag-and-drop and restoring from the Trash (0.1.2); 0.1.3 through the gate. arm64: static checks only.
- **Linux** x86_64: CI AppImage under Xvfb + Openbox (X11), full pass; Wayland: CI smoke test on headless sway (0.1.3+). aarch64 (0.1.5): started under X11 and Wayland on GitHub's arm64 runners. Not tested: interactive Wayland, XDND, feature checks on aarch64.
