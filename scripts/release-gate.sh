#!/bin/sh
# release-gate.sh   decide whether dist/<VERSION> is ready to publish.
#
# Run from the app's project root (reads haiku-app.env). Looks only at raw
# evidence — the artifacts, the app's logs, OCR text, fixture logs, the CI
# run — never at a summary, and prints one line per check, then
# "GATE PASSED" or "GATE FAILED n of m". Exit status 1 on failure.
#
# A PASS means "ask the human", not "publish". Tagging, pushing a tag and
# `gh release create` need their explicit go-ahead.
set -u
[ -f haiku-app.env ] || { echo "release-gate: run from the project root (no haiku-app.env)" >&2; exit 2; }
. ./haiku-app.env
V=$VERSION
D=dist/$V
E=$D/evidence
DEB=${APP_CMD}_${V}-${REVISION}_amd64.deb          # tested in the vos-test VM
DEB_ARM64=${APP_CMD}_${V}-${REVISION}_arm64.deb    # static checks (no arm64 VM on x86 hosts)
HPKG=${APP_CMD}-${V}-${REVISION}-x86_64.hpkg
APPIMG=${APP_NAME}-${V}-x86_64.AppImage
APPIMG_ARM64=${APP_NAME}-${V}-aarch64.AppImage  # started in CI on arm64 hardware (X11 + Wayland)
PLATFORMS="haiku vos linux"
REQUIRED="install attrs launch $FEATURE_CHECKS log-clean quit"
pass=0 fail=0
ok()  { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1: $2"; fail=$((fail + 1)); }
field() { sed -n "s/^$2: *//p" "$1" 2>/dev/null | head -1; }
art() { case $1 in haiku) echo $HPKG ;; vos) echo $DEB ;; linux) echo $APPIMG ;; esac; }

HEAD=$(git rev-parse HEAD)
if git diff --quiet HEAD -- 2>/dev/null; then ok tree-clean; else bad tree-clean "tracked files changed since HEAD; commit, push and rebuild"; fi
if git branch -r --contains "$HEAD" 2>/dev/null | grep -q origin/; then ok head-pushed; else bad head-pushed "HEAD $HEAD is not on origin"; fi
if git check-ignore -q "$D/x" 2>/dev/null; then ok dist-ignored; else bad dist-ignored "dist/ is not in .gitignore"; fi

# version everywhere it lives
if head -1 packaging/debian/changelog 2>/dev/null | grep -q "($V-$REVISION)"; then ok "version changelog"; else bad "version changelog" "top entry is not $V-$REVISION"; fi
MA=$(echo "$V" | cut -d. -f1) MI=$(echo "$V" | cut -d. -f2) MN=$(echo "$V" | cut -d. -f3)
if tr -d ' \t\n' < "$RDEF" | grep -q "major=$MA,middle=$MI,minor=$MN,"; then ok "version rdef"; else bad "version rdef" "$RDEF app_version is not $V"; fi
if grep -qF "\"$APP_SIG\"" "$RDEF"; then ok "signature rdef"; else bad "signature rdef" "$RDEF app_signature is not $APP_SIG"; fi
if [ -s "$D/release-notes.md" ] && grep -q '^### Tested' "$D/release-notes.md"; then ok release-notes; else bad release-notes "$D/release-notes.md missing or has no '### Tested' section"; fi
# README screenshots (release.md phase 5): images under docs/screenshots/ that exist
shots=0
for img in $(grep -oE '\]\(docs/screenshots/[^)]+\.(png|jpg)\)' README.md 2>/dev/null | sed 's/^](//; s/)$//'); do
	[ -s "$img" ] && git ls-files --error-unmatch "$img" >/dev/null 2>&1 && shots=$((shots + 1))
done
[ $shots -ge 3 ] && ok "readme screenshots ($shots)" \
	|| bad "readme screenshots" "README.md shows $shots committed docs/screenshots/ images; need one per platform (3+)"

for p in $PLATFORMS; do
	a=$(art $p); f=$E/$p.txt
	if [ ! -s "$D/$a" ]; then bad "$p artifact" "$D/$a missing"; continue; fi
	if [ ! -s "$f" ]; then bad "$p evidence" "$f missing"; continue; fi
	sum=$(sha256sum "$D/$a" | cut -d' ' -f1)
	[ "$(field "$f" sha256)" = "$sum" ] && ok "$p sha256" || bad "$p sha256" "evidence is for a different file than $D/$a"
	[ "$(field "$f" commit)" = "$HEAD" ] && ok "$p commit" || bad "$p commit" "tested build is from '$(field "$f" commit)', HEAD is $HEAD"
	req=$REQUIRED
	[ "$p" = linux ] && req="$req wayland"    # the AppImage under Wayland as well as X11
	for c in $req; do
		grep -qE "^CHECK $c PASS" "$f" && ok "$p $c" || bad "$p $c" "no 'CHECK $c PASS' line in $f"
	done
	grep -qx 'RESULT: PASS' "$f" && ok "$p result" || bad "$p result" "no 'RESULT: PASS' line"
	# the app's own output while it was used
	l=$E/$p-app.log
	if [ ! -e "$l" ]; then bad "$p app-log" "$l missing"
	elif grep -qiE 'error|assert|crash|segment|abort|debugger|terminate|exception' "$l"; then
		bad "$p app-log" "$(grep -iE 'error|assert|crash|segment|abort|debugger|terminate|exception' "$l" | head -1)"
	else ok "$p app-log"; fi
	# app-specific raw evidence from haiku-app.env
	i=1
	while :; do
		eval "rule=\${EVIDENCE_$i:-}"
		[ -n "$rule" ] || break
		rf=$(echo "${rule%%|*}" | sed "s/{p}/$p/g"); rx=$(echo "${rule#*|}" | sed "s/{p}/$p/g")
		grep -qE "$rx" "$E/$rf" 2>/dev/null && ok "$p evidence $i" || bad "$p evidence $i" "/$rx/ not found in $E/$rf"
		i=$((i + 1))
	done
	[ $i -gt 1 ] || bad "$p evidence" "haiku-app.env defines no EVIDENCE_1"
done

field "$E/haiku.txt" os | grep -q 'hrev59866' && ok "haiku os" || bad "haiku os" "os: line does not show Haiku R1/beta6 (hrev59866)"
field "$E/vos.txt" os | grep -q '0\.6' && ok "vos os" || bad "vos os" "os: line does not show VitruvianOS 0.6.x"

# the AppImage and the .deb must be CI builds of HEAD (appimage.yml / deb.yml)
for pw in linux:appimage vos:deb; do     # workflow names (name: in appimage.yml / deb.yml)
	p=${pw%%:*} wf=${pw#*:}
	RUN=$(field "$E/$p.txt" ci-run)
	got=$(gh run view "$RUN" --json headSha,conclusion,workflowName -q '.headSha+" "+.conclusion+" "+.workflowName' 2>/dev/null)
	if [ -n "$RUN" ] && echo "$got" | grep -qx "$HEAD success $wf"; then
		ok "$p from CI run $RUN ($wf)"
	else bad "$p ci" "ci-run '$RUN' is not a successful $wf run of HEAD (got: $got)"; fi
done

# the arm64 .deb: VirtualBox can't run an arm64 guest here, so check it statically
if [ -s "$D/$DEB_ARM64" ]; then
	ok "vos-arm64 artifact"
	T=$(mktemp -d)
	dpkg-deb -x "$D/$DEB_ARM64" "$T" 2>/dev/null
	[ "$(dpkg-deb -f "$D/$DEB_ARM64" Architecture 2>/dev/null)" = arm64 ] && ok "vos-arm64 architecture" \
		|| bad "vos-arm64 architecture" "control file does not say arm64"
	[ "$(dpkg-deb -f "$D/$DEB_ARM64" Version 2>/dev/null)" = "$V-$REVISION" ] && ok "vos-arm64 version" \
		|| bad "vos-arm64 version" "control Version is not $V-$REVISION"
	[ "$(od -An -tx1 -j18 -N1 "$T/system/apps/$APP_NAME" 2>/dev/null | tr -d ' ')" = b7 ] \
		&& ok "vos-arm64 aarch64 binary" || bad "vos-arm64 aarch64 binary" "system/apps/$APP_NAME is not an aarch64 ELF"
	rm -rf "$T"
	grep -q " $DEB_ARM64\$" "$D/SHA256SUMS" 2>/dev/null && ok "vos-arm64 in SHA256SUMS" \
		|| bad "vos-arm64 in SHA256SUMS" "$DEB_ARM64 is not listed"
else bad "vos-arm64 artifact" "$D/$DEB_ARM64 missing (deb.yml builds amd64 and arm64)"; fi

# the aarch64 AppImage: no arm64 desktop here, so appimage.yml starts it on GitHub's arm64
# runner under X11 and Wayland; the evidence cites those smoke results
f=$E/linux-arm64.txt
if [ ! -s "$D/$APPIMG_ARM64" ]; then bad "linux-arm64 artifact" "$D/$APPIMG_ARM64 missing (appimage.yml builds x86_64 and aarch64)"
elif [ ! -s "$f" ]; then bad "linux-arm64 evidence" "$f missing"
else
	ok "linux-arm64 artifact"
	[ "$(field "$f" sha256)" = "$(sha256sum "$D/$APPIMG_ARM64" | cut -d' ' -f1)" ] && ok "linux-arm64 sha256" \
		|| bad "linux-arm64 sha256" "evidence is for a different file than $D/$APPIMG_ARM64"
	[ "$(field "$f" commit)" = "$HEAD" ] && ok "linux-arm64 commit" || bad "linux-arm64 commit" "tested build is from '$(field "$f" commit)', HEAD is $HEAD"
	RUN=$(field "$f" ci-run)
	got=$(gh run view "$RUN" --json headSha,conclusion,workflowName -q '.headSha+" "+.conclusion+" "+.workflowName' 2>/dev/null)
	echo "$got" | grep -qx "$HEAD success appimage" && ok "linux-arm64 from CI run $RUN" \
		|| bad "linux-arm64 ci" "ci-run '$RUN' is not a successful appimage run of HEAD (got: $got)"
	for c in install x11 wayland; do
		grep -qE "^CHECK $c PASS" "$f" && ok "linux-arm64 $c" || bad "linux-arm64 $c" "no 'CHECK $c PASS' line in $f"
	done
	grep -qx 'RESULT: PASS' "$f" && ok "linux-arm64 result" || bad "linux-arm64 result" "no 'RESULT: PASS' line"
	for l in $E/linux-arm64-x11.log $E/linux-arm64-wayland.log; do
		if [ ! -e "$l" ]; then bad "linux-arm64 log" "$l missing"
		elif grep -qiE 'error|assert|crash|segment|abort|debugger|terminate|exception' "$l"; then bad "linux-arm64 log" "$(grep -iE 'error|assert|crash|segment|abort|exception' "$l" | head -1)"
		else ok "linux-arm64 log $(basename "$l")"; fi
	done
	grep -q " $APPIMG_ARM64\$" "$D/SHA256SUMS" 2>/dev/null && ok "linux-arm64 in SHA256SUMS" || bad "linux-arm64 in SHA256SUMS" "$APPIMG_ARM64 is not listed"
fi

if [ -s "$D/SHA256SUMS" ] && (cd "$D" && sha256sum -c --quiet SHA256SUMS) >/dev/null 2>&1 \
	&& [ "$(grep -c . "$D/SHA256SUMS")" = 5 ]; then ok SHA256SUMS
else bad SHA256SUMS "$D/SHA256SUMS missing, wrong, or not exactly the 5 artifacts (hpkg, 2 debs, 2 AppImages)"; fi

echo
if [ $fail = 0 ]; then
	echo "GATE PASSED ($pass checks). STOP: show this output to the human and wait for their go-ahead before tagging or publishing."
	exit 0
fi
echo "GATE FAILED $fail of $((pass + fail))"
exit 1
