# Onboarding an app

The goal: every later step is driven by files in the repo, so building and
testing need no knowledge in your head. Templates are in
`T=$HOME/.claude/skills/beos-app-platforms/templates`.

At the end the repo has:

    haiku-app.env                      identity, version, metadata, test evidence rules
    Makefile                           the two-platform contract (below)
    packaging/build-hpkg.sh            from the template, unchanged
    packaging/description.txt          long description, plain text
    packaging/appimage/{build-appimage.sh,AppRun.in,fonts.conf}   unchanged
    packaging/appimage/icon.png        256x256 PNG
    .github/workflows/{appimage.yml,test.yml}                    unchanged
    tools/haiku-typecheck.sh           unchanged
    release/test-plan.md               how to exercise THIS app (below)
    .gitignore                         + the build outputs (below)

"Unchanged" means copy the template as is. Everything app-specific goes in
`haiku-app.env`. If a template can't handle the app, write down what is
missing in your report. Don't fork the template.

## 1. Read the app first

Nobody will tell you anything about the app. Find out these things
yourself, and write each answer as a `FOUND` line in your report, with the
command that showed it:

1. **Unfinished work.** Run `git status --short` and `git stash list`. For
   each modified file, read `git diff <file>` and decide:
   - It's a fix that builds: keep it and commit it on its own, with a
     message saying what it fixes.
   - It's unclear: leave it uncommitted and ask in the report.
   Never discard someone's changes.
2. **Release history.** Run `git tag`, `gh release list`, `git log
   --oneline | head -20`, and look for stray release files (`SHA256SUMS`,
   `*.hpkg`, `*.AppImage` in the tree).
   - The version in the .rdef has never been published: release that version.
   - It has been published: bump it (patch level unless the human said
     otherwise).
   - Delete stale release files from git; release files live in `dist/`.
3. **What the app is for, and what it needs from outside to do it.** Read
   the README and the main window's code. Then grep for the outside world:
   `grep -rnE 'socket|connect\(|termios|/dev/|http|BUrl|BFilePanel|entry_ref|B_REFS_RECEIVED' src | head -40`.
   Put the app in one of these classes, because it decides the feature
   test (§5):
   - **Documents**: opens, edits and saves files. The fixture is sample files.
   - **Network or device client**: talks to a server, radio, serial device
     or web API. The fixture is a fake of that peer, running on the host.
   - **Self-contained**: a game, calculator or viewer of built-in data. No
     fixture is needed; the test drives the UI and reads the result from
     the screen.
4. **Existing test doubles.** Run `grep -rliE 'mock|fake|stub|loopback|fixture' tests/ test/ 2>/dev/null`.
   A mock server or device in the unit tests is the fastest way to build
   the fixture. Read it and note which requests it answers.

Then read the rest:

- `README*`, the `.rdef` (signature, version), the Makefile, the existing
  tests and `packaging/`.
- List the libraries it links beyond the Haiku API (`grep -h '#include <'
  src -r | sort -u`, and LIBS in the Makefile): each one goes in
  `APP_LIBS`, `HPKG_REQUIRES_EXTRA`, `APPIMAGE_MUST_BUNDLE` and
  `APPIMAGE_APT_EXTRA`.
- List the image formats it reads or writes through the Translation Kit
  (`grep -rn 'BTranslationUtils\|BTranslatorRoster' src`): they go in
  `APPIMAGE_TRANSLATORS`. None = `""`; PNG alone covers app artwork.
- Find platform `#ifdef`s (`__HAIKU__`, `*_COSMOE`) and look up
  cosmoe-linux.md § Porting traps for every Haiku API the app uses that's listed there.
- If packaging already exists, compare it to the templates and say what
  differs. Keep anything that's app-specific and correct (extra files,
  MIME types), and move those values into `haiku-app.env`.

## 2. haiku-app.env

`cp $T/haiku-app.env .` and fill in every field. Each one is commented.
These must agree, and the gate checks them:
- `APP_SIG` = `resource app_signature` in the .rdef
- `VERSION` = the .rdef `app_version` (`major`/`middle`/`minor`)
- `APP_NAME` = the Makefile `NAME` = the binary's file name

A network or device client must not reach a real service from CI: set `SMOKE_ARGS` to
whatever points it at nothing real (e.g. a server address of `127.0.0.1`). The smoke tests
start the app with those arguments; a template that doesn't fit an app gets an option like
this, in the skill, rather than a forked copy in the app.

Haiku licence names must match a file in `/boot/system/data/licenses` on
the Haiku VM (`ssh haiku-b6-test ls /boot/system/data/licenses`), e.g.
`GNU GPL v3`, `MIT`. If none matches, the package must ship the licence
text under that name. `package create` reports the problem.

## 3. Makefile contract

If the app has no Makefile, start from `$T/Makefile` and fill in `SRCS`,
`INCLUDES`, `APP_LIBS` and the `test` target. If it has one, make sure it
meets this contract:

1. `make` builds `./$APP_NAME` on Haiku and with Cosmoe
   (`COSMOE_ROOT=<prefix>`). Otherwise it prints what's missing and fails.
2. On Haiku it compiles the .rdef to `obj/$APP_NAME.rsrc` and applies it
   with `xres`. On Cosmoe it links it in as `.cosmoe_rsrc` (`obj/$APP_NAME.rsrc.o`).
3. Flags are additive (`override CXXFLAGS +=`), so `CXXFLAGS=`/`LDFLAGS=`
   given on the command line add to the Makefile's own.
4. The app's own libraries are linked on **every** platform branch.
5. `make clean` removes `obj/` and the binary.
6. `TEST_CMD` (usually `make test`) runs the host-side tests and needs no
   Haiku headers. If the app has no tests, set `TEST_CMD=""`. Don't invent
   tests here.

Check it on the host: `make tests` or `$TEST_CMD`, then
`sh tools/haiku-typecheck.sh` (it type-checks the UI sources against real
Haiku headers).

## 4. Packaging and CI

    mkdir -p packaging/appimage .github/workflows tools release
    cp $T/packaging/build-hpkg.sh packaging/
    cp $T/packaging/appimage/* packaging/appimage/
    cp $T/.github/workflows/*.yml .github/workflows/
    cp $T/tools/haiku-typecheck.sh tools/

- **Old packaging scripts** at other paths: delete them with `git rm`, and
  point the Makefile's `hpkg` target at the new one.
- **icon.png:** 256×256. If the app has none, draw a simple one with
  ImageMagick (`magick -size 256x256 xc:none -fill '#3b7dd8' -draw
  'roundrectangle 16,16 240,240 40,40' -fill white -pointsize 150 -gravity
  center -annotate 0 '<initial>' packaging/appimage/icon.png`) and say so in
  the report.
- **.gitignore:** add `/<APP_NAME>`, `obj/`, `dist/`, `*.hpkg`,
  `*.AppImage`, `.cosmoe/`, `.haiku-headers/`.
- **Old CI** that builds release files some other way: replace it with the
  templates. Release AppImages come only from `appimage.yml`.

## 5. release/test-plan.md — how to use THIS app

release-test.md runs the standard checks (install, attrs, launch, log-clean,
quit) the same way for every app. The test plan adds the app's own features.
Write it for a tester who can only read screens through OCR. Name UI
elements by their **labels**, never by coordinates:

    # Test plan: <App>
    ## Fixtures
    <anything the app needs to do real work: sample files, a mock server, a
     fake device. How to build and start it on the host, which address the
     guest uses (the host's LAN IP for VMs: `ip route get 1.1.1.1 | grep -oP
     'src \K\S+'`; 127.0.0.1 under Xvfb), and where its log goes:
     dist/V/evidence/{p}-<name>.log>
    ## Fresh state
    <settings/data dirs to delete before launch, per platform>
    ## Feature checks
    ### <check name, as in FEATURE_CHECKS>
    Steps: <click the "X" button; type "hello from {p}" in the "Message" field; ...>
    PASS when: <a raw-evidence fact, e.g. "the fixture log has SEND_TXT_MSG
    with 'hello from {p}'", "OCR of the window shows 'alice'">

Then add one `EVIDENCE_n="file|regex"` line to `haiku-app.env` for each
PASS condition, so the gate checks the raw files itself. Use `{p}` in
anything typed, so each platform's evidence is different.

**Good feature checks** prove the app's main job works end to end on that
platform: a document saved and reopened, a message sent to a fixture, a
file imported. Two to four checks is enough. If the app talks to hardware
or a network service, write a **fixture** program on the host that
imitates it. Reuse the app's own test mocks if it has any: a mock in the
unit tests can usually become a standalone server in a few lines. Build it
with the host's compiler from `make` (e.g. a `make fixture` target), and
give it a log line for every request it receives.

Prove the fixture works before using it in a test: start it, poke it from
the host (`nc`, `curl`, a small Python client), and show the log line.

## 6. Finish

    git add <each file by name>
    git commit -m "Set up the release pipeline" -m "<your harness's attribution line>"

Report every value you put in `haiku-app.env` that you had to infer, with
its source, using `DECISION` lines.
