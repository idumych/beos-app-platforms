# Releasing an app on both platforms

The pipeline runs from files in the app's repo, so it needs no knowledge in your head: set the
app up once (onboard.md), then build, test every package on its real platform, and stop at
the release gate. A human must say "publish" before anything is tagged or released.

Tools, run from the app's project root:

    S=$HOME/.claude/skills/beos-app-platforms; P=$S/scripts; T=$S/templates
    $P/check-artifact.sh hpkg|appimage FILE          static package checks
    $P/release-gate.sh                               the final yes/no
    $P/ocr-find.sh SHOT.png [WORD|--text]            a screenshot as text + click positions
    VM=<vm> SCRATCH=<dir> sh $P/vm.sh …              keys, text, mouse, screenshots in a VM
    APP=… APP_NAME=… SCRATCH=<dir> sh $P/xtest.sh …  the same under Xvfb (Linux)

If you can't view images, read every screenshot with `ocr-find.sh`, which prints each word with
the X Y to click. Either way, take a fresh screenshot before every click.

| Artifact | File in `dist/V/` | Built where |
|---|---|---|
| Haiku R1/beta6 (installs on Renku too) | `<APP_CMD>-<V>-<REVISION>-x86_64.hpkg` | inside the `haiku-b6-test` VM |
| Linux | `<APP_NAME>-<V>-x86_64.AppImage`, `-aarch64.AppImage` | GitHub Actions, `appimage.yml` (Ubuntu 24.04, Hokku, one job per arch; each starts its AppImage under X11 and Wayland) |

A Linux-only port (`PLATFORMS="linux"` in `haiku-app.env`) skips everything about the
`.hpkg` and the Haiku VM: phases 3 and the hpkg half of 6 and 7, and the hpkg in
`SHA256SUMS` and `gh release create`. The gate then checks the AppImages only.

A Haiku-only app (`PLATFORMS="haiku"`) is the mirror image: no `appimage.yml`, no Cosmoe,
no Linux half of phases 4, 6 and 7, and `SHA256SUMS` holds the `.hpkg` (and an arm64
one, if built). Use it only when the app can't work on Linux at all, not when the port is
just unfinished, and say why in the README and the release notes' "Tested" section (e.g.
"Linux: not available; the app runs VPN tunnels through Haiku's own network stack").
The gate prints the platforms it checked on its first line.

Both architectures on every platform that has an arm64 target (SKILL.md rules). Haiku arm64 is blocked for now (renku.md § arm64): check at each release.

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
    gh repo set-default "$GITHUB_REPO"    # a fork's clone otherwise points gh at upstream

`gh repo set-default` matters for apps forked from another project (EasyPaint): with an
`upstream` remote, `gh run list/view/download` without `-R` look in the upstream repo and
report "not found" for your runs.

## Phases

1. **Onboard** (onboard.md), once per app. Commit.
2. **Host checks:** `[ -z "$TEST_CMD" ] || sh -c "$TEST_CMD"`, then `sh tools/haiku-typecheck.sh`
   (last line `typecheck: N files, PASS`; it checks against Haiku's *current* headers, so beta6
   gaps like `AboutWindow.h` only show in the VM build).
3. **VM:** `haiku-b6-test` answers over SSH (release-test.md § Test VM).
4. **Push and CI** for HEAD (§ CI below). Build the .hpkg meanwhile.
5. **README screenshots** from this release candidate: one per platform (Haiku/Renku,
   Linux; the CI Wayland smoke shot counts for Linux), each showing a real feature
   with real content, cropped to the window (`magick shot.png -crop WxH+X+Y +repage`), pointer
   and tooltips out of the way (porting.md §7: closing stray windows and crash
   dialogs, moving a PS/2 pointer away, cropping a Haiku window by its
   frame). Save as `docs/screenshots/<platform>-<what>.png` and show them in
   `README.md` under `## Screenshots`, one-line caption each. Commit **before** the final build:
   the gate only accepts artifacts and evidence from HEAD, and wants 2+ screenshots.
6. **Final build** of both from that HEAD into `dist/V/`; `check-artifact.sh` on each.
   Any fix means commit, push, and rebuild **both**.
7. **Test** each artifact on its platform (release-test.md), producing `dist/V/evidence/`. A
   failure means fix the app, commit, push, back to 4.
8. **Notes and sums:** `dist/V/release-notes.md` (below), then
   `cd $D && sha256sum <hpkg> <x86_64.AppImage> <aarch64.AppImage> > SHA256SUMS`.
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

## CI: the AppImage

Never build it on a rolling-release host (CachyOS: newer glibc, x86-64-v3 libraries). Push, then:

    git push origin "$BRANCH"
    gh workflow run appimage.yml --ref "$BRANCH"
    for i in $(seq 30); do RUN=$(gh run list --workflow appimage.yml --branch "$BRANCH" --limit 5 \
    	--json databaseId,headSha,event \
    	-q "[.[] | select(.headSha==\"$HEAD\" and .event==\"workflow_dispatch\")][0].databaseId")
    	[ -n "$RUN" ] && break; sleep 5; done; echo "RUN=$RUN"
    echo $RUN > $D/ci-run
    timeout 3600 gh run watch "$RUN" --exit-status

Run the watch in the background. Don't trust its exit status alone: it has returned 0 with the
aarch64 job failed. Check every job: `gh run view "$RUN" --json jobs -q '.jobs[] | .name+" "+.conclusion'`. A first run takes 20–30 minutes (Hokku), later ones come from
the cache. When done:

    for a in x86_64 aarch64; do
    	gh run download "$RUN" -n AppImage-$a -D $D/; gh run download "$RUN" -n smoke-$a -D $D/smoke-$a
    	$P/check-artifact.sh appimage $D/${APP_NAME}-${V}-$a.AppImage
    done

`check-artifact.sh` unpacks the aarch64 AppImage on an x86 host through `qemu-aarch64`
(qemu-user) or `unsquashfs` (squashfs-tools); with neither installed, its `binary` check fails.

A failed run: `gh run view <id> --log-failed | tail -80`. Usual causes: a `-dev` package missing
from `APPIMAGE_APT_EXTRA`; a Makefile Cosmoe branch without the app's libraries; a porting trap
(cosmoe-linux.md).

## Release notes (`dist/V/release-notes.md`)

    ## <App> <V>
    <2–4 sentences: what the app is; what changed since the last release.>
    ### Downloads
    | Platform | File |              one row per artifact
    ### Install
    Haiku R1/beta6: `pkgman install ./<cmd>-<V>-1-x86_64.hpkg`
    Linux (glibc 2.39+): `chmod +x <App>-<V>-x86_64.AppImage && ./<App>-<V>-x86_64.AppImage` (`-aarch64` on ARM)
    ### Tested
    One line per platform: the OS and version from the evidence `os:` line, and what was
    exercised. Then say plainly what was NOT tested (the aarch64 AppImage was only started in CI; Haiku has no arm64 build; real hardware,
    interactive Wayland, Renku OS, drag and drop from a Linux file manager…).
    ### Checksums
    See SHA256SUMS.

Keep the README's platform table in step with "Tested".

## Publish — only after the human said "publish"

    git tag -a "v$V" -m "$APP_NAME $V" && git push origin "v$V"
    gh release create "v$V" $D/${APP_CMD}-${V}-${REVISION}-x86_64.hpkg $D/${APP_NAME}-${V}-x86_64.AppImage \
    	$D/${APP_NAME}-${V}-aarch64.AppImage \
    	$D/SHA256SUMS --title "$APP_NAME $V" --notes-file $D/release-notes.md --verify-tag

The tag starts `appimage.yml` again; it sees its files already attached and leaves them alone.
When they finish, check the release still holds exactly what you tested:

    mkdir -p $D/from-release && gh release download "v$V" -D $D/from-release --clobber
    (cd $D/from-release && sha256sum -c SHA256SUMS)
    gh release view "v$V" --json assets -q '.assets[].name'

Then re-test from the release URLs (release-test.md § After publishing). If `gh release create`
fails partway, don't delete or recreate anything: report the state and ask.

## Rules

- **Allowed:** edit and commit in the app repo; push the current branch; build; drive
  `haiku-b6-test`; `gh workflow run`, `gh run list/view/watch/download`; write in
  `dist/`, `obj/` and scratch dirs.
- **Needs a human go-ahead:** `git tag`, pushing tags, any `gh release` command that changes
  something, force pushes, history rewrites, creating a GitHub repo, deleting a VM, touching
  any other VM (cloning *from* a powered-off one is allowed), installing host packages.
- **Stage files by name.** Never `git add -A` / `git add .`: repos hold binaries, sysroots, `dist/`.
- **Commit messages** end with the attribution your harness asks for (a local Qwen run:
  `Assisted-by: Qwen (local)`).
- **A PASS is output you just saw.** Quote the command and the line it printed. A check you
  didn't run is a FAIL. Write evidence lines only after the condition was checked.
- **Never weaken a check.** Don't edit `check-artifact.sh`, `release-gate.sh`, tests or evidence
  to get a pass. If a check looks wrong, leave it failing and say why.
- **Processes:** `pkill -x <Name>`, never `pkill -f <pattern>`. `-x` matches the
  kernel's process name, which is cut to 15 characters (`AppImageLauncher` never matches);
  close such windows with `xdotool windowclose` instead. Wait with a bounded loop
  (`for i in $(seq 60); do <check> && break; sleep 5; done`), never an open-ended `sleep`.
- **Throwaway directories:** make a new one with `mktemp -d` rather than `rm -rf "$DIR"`;
  the harness may refuse a removal whose path is a variable.
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

- A Makefile's Cosmoe branch linked only `-lbe -ltracker` and forgot the app's own libraries.
  Put them in `APP_LIBS` once, for all platforms.
- A test VM already had an older version of the app installed. Remove it first.
- A docs commit after the build moved HEAD, and the gate rejected every artifact. Commit
  screenshots and README changes before the final build.
- An evidence script printed PASS lines unconditionally while the display it drove was dead.
  Make every PASS line depend on the check (see release-test.md).
- The aarch64 X11 smoke test passed with an all-black screenshot: it only checked that the
  process stayed up. The smoke scripts now fail on a one-colour screenshot and on a window
  that never becomes visible. Look at every screenshot you cite.
- A test passed while its screenshot contradicted the test plan (a black rectangle where the
  plan said red): the check only looked for the text. Turn every part of a PASS condition
  into code (a colour is a pixel read with PIL), and look at the shot anyway.
- A Haiku release retest failed because the VM's screen blanker was on: the first typed
  letter only woke it, so the file was saved as `asypaint-release.png`. Wake the screen
  before each interactive run (release-test.md § Haiku).
- `eval $(xdotool getwindowgeometry --shell …)` set `X`, which was the evidence file in the
  test script's `chk` helper, so later checks were written to files named `239` and `240`
  in the project root. Prefix its variables (release-test.md § Driving the UI).
- On the slower arm64 runner, a window mapped while Openbox was still starting stayed unmapped.
  Start the app only once the WM answers EWMH queries (`xdotool get_desktop`); `x11-smoke.sh`
  does, and do the same when you start Xvfb + Openbox by hand.
