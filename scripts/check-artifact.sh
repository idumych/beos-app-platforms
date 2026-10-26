#!/bin/sh
# check-artifact.sh hpkg|appimage FILE [SSH_ALIAS]
#
# Static checks on a built package, before any install test. Run from the
# app's project root: names, version and signature come from haiku-app.env.
# Prints one "PASS name" / "FAIL name: detail" line per check, then
# "CHECKS PASSED n" or "CHECKS FAILED n of m". Exit status 1 on any failure.
#
#   hpkg      needs a Haiku guest: SSH_ALIAS (default haiku-b6-test); the
#             file is copied to /tmp there and read with Haiku's `package`
#   appimage  on the host; extracts into a temp dir
set -u
KIND=$1 FILE=$2 ALIAS=${3:-haiku-b6-test}
[ -f haiku-app.env ] || { echo "check-artifact: run from the project root (no haiku-app.env)" >&2; exit 2; }
. ./haiku-app.env
V="$VERSION-$REVISION"
APP_PATH=${APP_PATH:-apps/$APP_NAME}          # the app in the package, from /boot/system
DESKBAR_NAME=${DESKBAR_NAME:-$APP_NAME}       # its Deskbar menu entry
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
hpkg)
	chk name "basename '$FILE' | grep -qxE '${APP_CMD}-${V}-(x86_64|arm64).hpkg'" "file name is not ${APP_CMD}-${V}-x86_64.hpkg or -arm64.hpkg"
	case "$(basename "$FILE")" in *-arm64.hpkg) HARCH=arm64 ;; *) HARCH=x86_64 ;; esac
	scp -q "$FILE" "$ALIAS:/tmp/check.hpkg" || { echo "FAIL scp to $ALIAS"; echo "CHECKS FAILED 1 of 1"; exit 1; }
	# -i: meta information; -p: one path per line (bin/<cmd>...); -a: files with their attributes
	ssh "$ALIAS" 'package list -i /tmp/check.hpkg; echo ===; package list -p /tmp/check.hpkg; echo ===; package list -a /tmp/check.hpkg; rm -f /tmp/check.hpkg' > "$TMP/list" 2>&1
	L="$TMP/list"
	# From `package list -a` (the third section, a tree indented two spaces per
	# level, attributes as "<NAME ...>" under their file): APP_PATH's type and
	# whether it carries BEOS:APP_SIG
	awk -v want="$APP_PATH" '
		/^===/ { sec++; next }
		sec != 2 { next }
		{ match($0, /^ */); depth = RLENGTH / 2; line = substr($0, RLENGTH + 1) }
		line ~ /^</ { if (cur == want && line ~ /^<BEOS:APP_SIG /) sig = 1; next }
		{ split(line, f, /  +/); name[depth] = f[1]; cur = name[0]
		  for (i = 1; i <= depth; i++) cur = cur "/" name[i]
		  if (cur == want) type = substr($NF, 1, 1) }
		END { print (type == "-" ? "file" : type == "" ? "missing" : "not-a-file"), (sig ? "sig" : "nosig") }
	' "$L" > "$TMP/app"
	chk version "grep -qE 'version:? *$V' '$L'" "PackageInfo version is not $V"
	chk "architecture $HARCH" "grep -qE 'architecture:? *$HARCH' '$L'"
	chk requires-beta6 "grep -qE 'haiku *>= *r1~beta6' '$L'" "does not require haiku >= r1~beta6"
	chk apps-binary "grep -q '^file ' '$TMP/app'" "$APP_PATH is $(cut -d' ' -f1 "$TMP/app") in the package (APP_PATH)"
	chk bin-link "grep -q 'bin/$APP_CMD' '$L'"
	chk deskbar-link "grep -qF 'deskbar/menu/Applications/$DESKBAR_NAME' '$L'" "no Deskbar entry named '$DESKBAR_NAME' (DESKBAR_NAME)"
	chk app-sig-attr "grep -q ' sig\$' '$TMP/app'" "$APP_PATH has no BEOS:APP_SIG attribute (rdef not compiled in, or mimeset missing)"
	for r in ${HPKG_REQUIRES_EXTRA:-}; do chk "requires $r" "grep -qF '$r' '$L'"; done
	;;
appimage)
	chk name "basename '$FILE' | grep -qxE '${APP_NAME}-${VERSION}-(x86_64|aarch64).AppImage'" "file name is not ${APP_NAME}-${VERSION}-x86_64.AppImage or -aarch64.AppImage"
	case "$(basename "$FILE")" in *-aarch64.AppImage) AARCH=aarch64 EM=b7 ;; *) AARCH=x86_64 EM=3e ;; esac
	cp "$FILE" "$TMP/a.AppImage" && chmod +x "$TMP/a.AppImage"
	# Unpack without needing to run it natively: run the runtime directly on a matching
	# host, through qemu-user for the other architecture, or read the squashfs that follows
	# the runtime's ELF image with unsquashfs.
	if [ "$(uname -m)" = "$AARCH" ] || { [ "$AARCH" = aarch64 ] && [ "$(uname -m)" = arm64 ]; }; then
		( cd "$TMP" && APPIMAGE_EXTRACT_AND_RUN=1 ./a.AppImage --appimage-extract >/dev/null 2>&1 )
	elif command -v "qemu-$AARCH" >/dev/null 2>&1; then
		( cd "$TMP" && "qemu-$AARCH" ./a.AppImage --appimage-extract >/dev/null 2>&1 )
	elif command -v unsquashfs >/dev/null 2>&1; then
		OFF=$(python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(64); sh=struct.unpack_from("<Q",d,40)[0]; es,n=struct.unpack_from("<HH",d,58); print(sh+es*n)' "$TMP/a.AppImage")
		unsquashfs -q -d "$TMP/squashfs-root" -o "$OFF" "$TMP/a.AppImage" >/dev/null 2>&1
	fi
	R="$TMP/squashfs-root"
	# the executable is usr/bin/<App>, or usr/bin/<cmd> for apps whose binary is the command
	BIN=$APP_NAME; [ -e "$R/usr/bin/$BIN" ] || BIN=$APP_CMD
	chk binary "test -s '$R/usr/bin/$BIN'" "could not unpack it (for $AARCH on $(uname -m) install qemu-user or squashfs-tools), or usr/bin/$BIN is missing"
	chk "$AARCH binary" "[ \"\$(od -An -tx1 -j18 -N1 '$R/usr/bin/$BIN' | tr -d ' ')\" = $EM ]" "usr/bin/$BIN is not an $AARCH ELF"
	chk rsrc-section "readelf -S '$R/usr/bin/$BIN' | grep -q cosmoe_rsrc" "no .cosmoe_rsrc section (resources not linked in)"
	chk signature "strings -a '$R/usr/bin/$BIN' | grep -qF '$APP_SIG'"
	chk libbe "ls '$R'/usr/lib/libbe.so*"
	chk libbe-runpath "readelf -d \$(ls '$R'/usr/lib/libbe.so* | head -1) | grep RUNPATH | grep -q '\[\$ORIGIN\]'" \
		"libbe RUNPATH is not exactly \$ORIGIN (host libraries would win)"
	chk backend-x11 "find '$R' -name 'libcosmoe-x11.so*' | grep -q ."
	chk backend-wayland "find '$R' -name 'libcosmoe-wayland.so*' | grep -q ."
	for l in ${APPIMAGE_MUST_BUNDLE:-}; do chk "bundled $l" "ls '$R'/usr/lib/$l.so*" "$l is not bundled in usr/lib"; done
	G=$(glibc_max $(find "$R" -type f \( -name '*.so*' -o -path '*/usr/bin/*' \)))
	chk "glibc<=2.39 ($G)" "le '$G' GLIBC_2.39" "needs $G; must run on Ubuntu 24.04 (2.39). Built on this host instead of CI?"
	;;
*) echo "usage: check-artifact.sh hpkg|appimage FILE [SSH_ALIAS]" >&2; exit 2 ;;
esac

if [ $fail = 0 ] && [ $pass -gt 0 ]; then echo "CHECKS PASSED $pass"; exit 0; fi
echo "CHECKS FAILED $fail of $((pass + fail))"; exit 1
