#!/bin/sh
# check-artifact.sh deb|hpkg|appimage FILE [SSH_ALIAS]
#
# Static checks on a built package, before any install test. Run from the
# app's project root: names, version and signature come from haiku-app.env.
# Prints one "PASS name" / "FAIL name: detail" line per check, then
# "CHECKS PASSED n" or "CHECKS FAILED n of m". Exit status 1 on any failure.
#
#   deb       on the host (dpkg-deb, objdump)
#   hpkg      needs a Haiku guest: SSH_ALIAS (default haiku-b6-test); the
#             file is copied to /tmp there and read with Haiku's `package`
#   appimage  on the host; extracts into a temp dir
set -u
KIND=$1 FILE=$2 ALIAS=${3:-haiku-b6-test}
[ -f haiku-app.env ] || { echo "check-artifact: run from the project root (no haiku-app.env)" >&2; exit 2; }
. ./haiku-app.env
V="$VERSION-$REVISION"
pass=0 fail=0
ok()  { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1: $2"; fail=$((fail + 1)); }
chk() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1" "${3:-$2}"; fi; }
glibc_max() { objdump -T "$@" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -1; }
le() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]; }   # $1 <= $2
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
[ -s "$FILE" ] || { echo "FAIL exists: $FILE missing or empty"; echo "CHECKS FAILED 1 of 1"; exit 1; }

case "$KIND" in
deb)
	chk name "basename '$FILE' | grep -qxE '${APP_CMD}_${V}_(amd64|arm64).deb'" "file name is not ${APP_CMD}_${V}_amd64.deb or _arm64.deb"
	I=$(dpkg-deb -I "$FILE")
	chk version "echo \"\$I\" | grep -qx ' Version: $V'" "control Version is not $V"
	chk depends-vos "echo \"\$I\" | grep -q 'Depends: vos (>= '" "no vos dependency"
	dpkg-deb -x "$FILE" "$TMP/root"
	dpkg-deb -e "$FILE" "$TMP/ctl"
	B="$TMP/root/system/apps/$APP_NAME"
	chk binary-nonempty "test -s '$B'" "/system/apps/$APP_NAME missing or empty"
	chk binary-elf "head -c4 '$B' | grep -q ELF" "not an ELF file"
	chk signature "strings -a '$B' | grep -qF '$APP_SIG'" "app signature resource missing (stripped after xres?)"
	chk deskbar-link "test -L '$TMP/root/system/data/deskbar/menu/Applications/$APP_NAME'"
	chk usr-bin-link "test -L '$TMP/root/usr/bin/$APP_CMD'"
	chk attrs-tar "test -s '$TMP/root/usr/share/$APP_CMD/apps_attrs.tar'"
	mkdir -p "$TMP/attrs"
	chk attrs-has-sig "tar --xattrs --xattrs-include='user.*' -xf '$TMP/root/usr/share/$APP_CMD/apps_attrs.tar' -C '$TMP/attrs' && getfattr -d -m user.beos '$TMP/attrs/system/apps/$APP_NAME' | grep -q APP_SIG" \
		"the attribute tarball has no user.beos.BEOS:APP_SIG"
	# the tarball holds an EMPTY placeholder: postinst must copy attributes
	# onto the real binary, never move or copy the file over it
	chk postinst-keeps-binary "! grep -E '^[^#]*(mv|cp|install) .*/system/apps' '$TMP/ctl/postinst'" \
		"postinst moves or copies a file into /system/apps (would replace the binary with the empty placeholder)"
	chk postinst-sets-attrs "grep -q setfattr '$TMP/ctl/postinst'" "postinst never calls setfattr"
	G=$(glibc_max "$B")
	chk "glibc<=2.41 ($G)" "le '$G' GLIBC_2.41" "needs $G; VitruvianOS 0.6 (Debian trixie) has 2.41"
	;;
hpkg)
	chk name "basename '$FILE' | grep -qx '${APP_CMD}-${V}-x86_64.hpkg'" "file name is not ${APP_CMD}-${V}-x86_64.hpkg"
	scp -q "$FILE" "$ALIAS:/tmp/check.hpkg" || { echo "FAIL scp to $ALIAS"; echo "CHECKS FAILED 1 of 1"; exit 1; }
	# -i: meta information; -p: one path per line (bin/<cmd>...); -a: files with their attributes
	ssh "$ALIAS" 'package list -i /tmp/check.hpkg; echo ===; package list -p /tmp/check.hpkg; echo ===; package list -a /tmp/check.hpkg; rm -f /tmp/check.hpkg' > "$TMP/list" 2>&1
	L="$TMP/list"
	chk version "grep -qE 'version:? *$V' '$L'" "PackageInfo version is not $V"
	chk requires-beta6 "grep -qE 'haiku *>= *r1~beta6' '$L'" "does not require haiku >= r1~beta6"
	chk apps-binary "grep -q 'apps/$APP_NAME' '$L'"
	chk bin-link "grep -q 'bin/$APP_CMD' '$L'"
	chk deskbar-link "grep -q 'deskbar/menu/Applications/$APP_NAME' '$L'"
	chk app-sig-attr "grep -q 'BEOS:APP_SIG' '$L'" "no BEOS:APP_SIG attribute (rdef not compiled in, or mimeset missing)"
	for r in ${HPKG_REQUIRES_EXTRA:-}; do chk "requires $r" "grep -qF '$r' '$L'"; done
	;;
appimage)
	chk name "basename '$FILE' | grep -qx '${APP_NAME}-${VERSION}-x86_64.AppImage'" "file name is not ${APP_NAME}-${VERSION}-x86_64.AppImage"
	cp "$FILE" "$TMP/a.AppImage" && chmod +x "$TMP/a.AppImage"
	( cd "$TMP" && APPIMAGE_EXTRACT_AND_RUN=1 ./a.AppImage --appimage-extract >/dev/null 2>&1 )
	R="$TMP/squashfs-root"
	chk binary "test -s '$R/usr/bin/$APP_NAME'"
	chk rsrc-section "readelf -S '$R/usr/bin/$APP_NAME' | grep -q cosmoe_rsrc" "no .cosmoe_rsrc section (resources not linked in)"
	chk signature "strings -a '$R/usr/bin/$APP_NAME' | grep -qF '$APP_SIG'"
	chk libbe "ls '$R'/usr/lib/libbe.so*"
	chk libbe-runpath "readelf -d \$(ls '$R'/usr/lib/libbe.so* | head -1) | grep RUNPATH | grep -q '\[\$ORIGIN\]'" \
		"libbe RUNPATH is not exactly \$ORIGIN (host libraries would win)"
	chk backend-x11 "find '$R' -name 'libcosmoe-x11.so*' | grep -q ."
	chk backend-wayland "find '$R' -name 'libcosmoe-wayland.so*' | grep -q ."
	for l in ${APPIMAGE_MUST_BUNDLE:-}; do chk "bundled $l" "ls '$R'/usr/lib/$l.so*" "$l is not bundled in usr/lib"; done
	G=$(glibc_max $(find "$R" -type f \( -name '*.so*' -o -path '*/usr/bin/*' \)))
	chk "glibc<=2.39 ($G)" "le '$G' GLIBC_2.39" "needs $G; must run on Ubuntu 24.04 (2.39). Built on this host instead of CI?"
	;;
*) echo "usage: check-artifact.sh deb|hpkg|appimage FILE [SSH_ALIAS]" >&2; exit 2 ;;
esac

if [ $fail = 0 ] && [ $pass -gt 0 ]; then echo "CHECKS PASSED $pass"; exit 0; fi
echo "CHECKS FAILED $fail of $((pass + fail))"; exit 1
