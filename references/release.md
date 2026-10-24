# Releasing an app on all three platforms

The pipeline runs from files in the app's repo, so it needs no knowledge in your head: set the
app up once (onboard.md), then build, test every package on its real platform, and stop at
the release gate. A human must say "publish" before anything is tagged or released.

Tools, run from the app's project root:

    S=$HOME/.claude/skills/beos-app-platforms; P=$S/scripts; T=$S/templates
    $P/check-artifact.sh deb|hpkg|appimage FILE      static package checks
    $P/release-gate.sh                               the final yes/no
    $P/ocr-find.sh SHOT.png [WORD|--text]            a screenshot as text + click positions
    VM=<vm> SCRATCH=<dir> sh $P/vm.sh …              keys, text, mouse, screenshots in a VM
    APP=… APP_NAME=… SCRATCH=<dir> sh $P/xtest.sh …  the same under Xvfb (Linux)

If you can't view images, read every screenshot with `ocr-find.sh`, which prints each word with
the X Y to click. Either way, take a fresh screenshot before every click.

| Artifact | File in `dist/V/` | Built where |
|---|---|---|
| Haiku R1/beta6 (installs on Renku too) | `<APP_CMD>-<V>-<REVISION>-x86_64.hpkg` | inside the `haiku-b6-test` VM |
| VitruvianOS | `<APP_CMD>_<V>-<REVISION>_amd64.deb`, `_arm64.deb` | GitHub Actions, `deb.yml` (debian:trixie, one job per arch) |
| Linux | `<APP_NAME>-<V>-x86_64.AppImage` | GitHub Actions, `appimage.yml` (Ubuntu 24.04, Hokku; also smoke-tests Wayland) |

## Starting cold

The request may be one line ("release meshy-haiku"). Finding the facts about the app is part
of the job (onboard.md §1). If something truly can't be decided from the repo, pick the safe
option, write `DECISION … because …`, and carry on.

Everything for version V goes in `dist/V/` (git-ignored), with a log in `dist/V/STATE.md`. At
the start of each session, read it and resume at the first phase not marked done. After each
phase append `<n> <phase> DONE <date> <short commit> <one-line result>`.

Every session starts with:

    . ./haiku-app.env; V=$VERSION; D=dist/$V; mkdir -p $D/evidence $D/shots
    HEAD=$(git rev-parse HEAD); BRANCH=$(git branch --show-current)

## Phases

1. **Onboard** (onboard.md), once per app. Commit.
2. **Host checks:** `[ -z "$TEST_CMD" ] || sh -c "$TEST_CMD"`, then `sh tools/haiku-typecheck.sh`
   (last line `typecheck: N files, PASS`; it checks against Haiku's *current* headers, so beta6
   gaps like `AboutWindow.h` only show in the VM build). Optional V\OS link check if an SDK
   exists on the host: `( . <sdk>/env.sh && make clean && make )`, then delete the result.
3. **VMs:** `haiku-b6-test` and `vos-test` answer over SSH (release-test.md § Test VMs).
4. **Push and CI** for HEAD (§ CI below). Build the .hpkg meanwhile.
5. **README screenshots** from this release candidate: one per platform (Haiku/Renku,
   VitruvianOS, Linux; the CI Wayland smoke shot counts for Linux), each showing a real feature
   with real content, cropped to the window (`magick shot.png -crop WxH+X+Y +repage`), pointer
   and tooltips out of the way. Save as `docs/screenshots/<platform>-<what>.png` and show them in
   `README.md` under `## Screenshots`, one-line caption each. Commit **before** the final build:
   the gate only accepts artifacts and evidence from HEAD, and wants 3+ screenshots.
6. **Final build** of all three from that HEAD into `dist/V/`; `check-artifact.sh` on each.
   Any fix means commit, push, and rebuild **all three**.
7. **Test** each artifact on its platform (release-test.md), producing `dist/V/evidence/`. A
   failure means fix the app, commit, push, back to 4.
8. **Notes and sums:** `dist/V/release-notes.md` (below), then
   `cd $D && sha256sum <amd64.deb> <arm64.deb> <hpkg> <AppImage> > SHA256SUMS`.
9. **Gate:** `$P/release-gate.sh`. Fix what it names. When it prints `GATE PASSED`, **stop**:
   report its output and wait for the human.
10. **Publish** (only after the human says so; § Publish), then re-test from the release URLs.

## Build the .hpkg (inside haiku-b6-test)

    ssh haiku-b6-test "pkgman install -y $HPKG_BUILD_DEPS" | tail -3     # skip if empty
    git archive --prefix=src/ HEAD | ssh haiku-b6-test \
      "rm -rf ~/build/$APP_CMD && mkdir -p ~/build/$APP_CMD && tar -x -C ~/build/$APP_CMD \
       && cd ~/build/$APP_CMD/src && find . -exec touch {} + && sh packaging/build-hpkg.sh" 2>&1 | tail -30
    scp haiku-b6-test:build/$APP_CMD/src/${APP_CMD}-${V}-${REVISION}-x86_64.hpkg $D/
    $P/check-artifact.sh hpkg $D/${APP_CMD}-${V}-${REVISION}-x86_64.hpkg

- `git archive HEAD` holds only committed files: a fix missing from the VM build wasn't committed.
- `find … -exec touch` fixes the guest's clock skew ("time stamp in the future").
- Haiku-only compile errors: look in the guest's headers
  (`ssh haiku-b6-test grep -rn <Symbol> /boot/system/develop/headers/os`), not your memory.
- `package create` complaining about a licence: `LICENSE_NAME` isn't a file in
  `/boot/system/data/licenses`.
- No VM of your own? renku.md § Build an hpkg in GitHub CI. The gate still wants the test on
  Haiku R1/beta6.

## CI: the .debs and the AppImage

Never build these on a rolling-release host (CachyOS: newer glibc, x86-64-v3 libraries; a
host-built .deb once needed `cfsetispeed@GLIBC_2.42`, but V\OS has 2.41). Push, then:

    git push origin "$BRANCH"
    gh workflow run appimage.yml --ref "$BRANCH"; gh workflow run deb.yml --ref "$BRANCH"
    runid() { gh run list --workflow "$1" --branch "$BRANCH" --limit 5 --json databaseId,headSha,event \
    	-q "[.[] | select(.headSha==\"$HEAD\" and .event==\"workflow_dispatch\")][0].databaseId"; }
    for i in $(seq 30); do RUN=$(runid appimage.yml); DEB_RUN=$(runid deb.yml)
    	[ -n "$RUN" ] && [ -n "$DEB_RUN" ] && break; sleep 5; done; echo "RUN=$RUN DEB_RUN=$DEB_RUN"
    echo $RUN > $D/ci-run; echo $DEB_RUN > $D/deb-run
    timeout 3600 gh run watch "$RUN" --exit-status; timeout 3600 gh run watch "$DEB_RUN" --exit-status

Run the watches in the background. First runs take 20–30 minutes (Hokku, the V\OS SDK), later
ones come from the cache. When done:

    gh run download "$RUN" -n AppImage -D $D/; gh run download "$RUN" -n wayland-smoke -D $D/wayland-smoke
    gh run download "$DEB_RUN" -n deb-amd64 -D $D/; gh run download "$DEB_RUN" -n deb-arm64 -D $D/
    for f in $D/*.deb; do $P/check-artifact.sh deb $f; done
    $P/check-artifact.sh appimage $D/${APP_NAME}-${V}-x86_64.AppImage

A failed run: `gh run view <id> --log-failed | tail -80`. Usual causes: a `-dev` package missing
from `APPIMAGE_APT_EXTRA`/`DEB_APT_EXTRA`; a Makefile Cosmoe branch without the app's libraries;
a porting trap (cosmoe-linux.md); an SDK build error in `make-sdk.sh` (report it exactly: the
script is a shared template). glibc > 2.41 on a CI .deb means a dependency is too new: read the
log's "glibc needed" line.

## Release notes (`dist/V/release-notes.md`)

    ## <App> <V>
    <2–4 sentences: what the app is; what changed since the last release>
    ### Downloads
    | Platform | File |              one row per artifact
    ### Install
    Haiku R1/beta6: `pkgman install ./<cmd>-<V>-1-x86_64.hpkg`
    VitruvianOS 0.6: `sudo apt install ./<cmd>_<V>-1_amd64.deb` (or `_arm64.deb` on ARM)
    Linux (x86_64, glibc 2.39+): `chmod +x <App>-<V>-x86_64.AppImage && ./<App>-<V>-x86_64.AppImage`
    ### Tested
    One line per platform: the OS and version from the evidence `os:` line, and what was
    exercised. Then say plainly what was NOT tested (the arm64 .deb was not run, real hardware,
    interactive Wayland, Renku OS, drag and drop from a Linux file manager…).
    ### Checksums
    See SHA256SUMS.

Keep the README's platform table in step with "Tested".

## Publish — only after the human said "publish"

    git tag -a "v$V" -m "$APP_NAME $V" && git push origin "v$V"
    gh release create "v$V" $D/${APP_CMD}_${V}-${REVISION}_amd64.deb $D/${APP_CMD}_${V}-${REVISION}_arm64.deb \
    	$D/${APP_CMD}-${V}-${REVISION}-x86_64.hpkg $D/${APP_NAME}-${V}-x86_64.AppImage \
    	$D/SHA256SUMS --title "$APP_NAME $V" --notes-file $D/release-notes.md --verify-tag

The tag starts both workflows again; each sees its file already attached and leaves it alone.
When they finish, check the release still holds exactly what you tested:

    mkdir -p $D/from-release && gh release download "v$V" -D $D/from-release --clobber
    (cd $D/from-release && sha256sum -c SHA256SUMS)
    gh release view "v$V" --json assets -q '.assets[].name'

Then re-test from the release URLs (release-test.md § After publishing). If `gh release create`
fails partway, don't delete or recreate anything: report the state and ask.

## Rules

- **Allowed:** edit and commit in the app repo; push the current branch; build; drive
  `haiku-b6-test` / `vos-test`; `gh workflow run`, `gh run list/view/watch/download`; write in
  `dist/`, `obj/` and scratch dirs.
- **Needs a human go-ahead:** `git tag`, pushing tags, any `gh release` command that changes
  something, force pushes, history rewrites, creating a GitHub repo, deleting a VM, touching
  any other VM (cloning *from* a powered-off one is allowed), installing host packages.
- **Stage files by name.** Never `git add -A` / `git add .`: repos hold binaries, SDKs, `dist/`.
- **Commit messages** end with the attribution your harness asks for (a local Qwen run:
  `Assisted-by: Qwen (local)`).
- **A PASS is output you just saw.** Quote the command and the line it printed. A check you
  didn't run is a FAIL. Write evidence lines only after the condition was checked.
- **Never weaken a check.** Don't edit `check-artifact.sh`, `release-gate.sh`, tests or evidence
  to get a pass. If a check looks wrong, leave it failing and say why.
- **Processes:** `pkill -x <Name>`, never `pkill -f <pattern>`. Wait with a bounded loop
  (`for i in $(seq 60); do <check> && break; sleep 5; done`), never an open-ended `sleep`.
- **Long jobs** (CI, VM boot, Hokku build) run with a timeout or in the background; don't block
  for more than 10 minutes.
- Upstream bugs go in your report for the human (and SKILL.md's rules on where they're filed).

## Report (end of every session)

    PHASE <n> <name>: DONE | BLOCKED
    <command> -> <line it printed>            one per check you ran
    DECISION <what> because <source>           one per non-obvious choice
    PROBLEM <what failed> / <what you tried>   if any
    NEXT <next phase, or "waiting for go-ahead to publish">

## Mistakes seen

- A .deb postinst moved the attribute placeholder, an **empty** file, over the binary: the app
  was 0 bytes. The template postinst copies attributes with `getfattr | setfattr --restore`, and
  `check-artifact.sh deb` catches the bad pattern.
- A Makefile's Cosmoe branch linked only `-lbe -ltracker` and forgot the app's own libraries.
  Put them in `APP_LIBS` once, for all platforms.
- A test VM already had an older version of the app installed. Remove it first.
- A docs commit after the build moved HEAD, and the gate rejected every artifact. Commit
  screenshots and README changes before the final build.
- An evidence script printed PASS lines unconditionally while the display it drove was dead.
  Make every PASS line depend on the check (see release-test.md).
