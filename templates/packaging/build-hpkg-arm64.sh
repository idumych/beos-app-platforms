#!/bin/sh
# build-hpkg-arm64.sh — builds <cmd>-<version>-<revision>-arm64.hpkg on Linux, with Haiku's
# cross toolchain and a sysroot of Haiku's arm64 packages. Generic beos-app-platforms
# template: everything app-specific comes from haiku-app.env.
#
#   sh tools/haiku-arm64/make-sysroot.sh ~/.cache/haiku-arm64     (once, ~20 min)
#   . ~/.cache/haiku-arm64/env.sh
#   sh tools/haiku-arm64/build-deps.sh       (once; only if the app needs HaikuPorts libraries)
#   sh packaging/build-hpkg-arm64.sh
#
# HaikuPorts has no arm64 repository, so the package requires only haiku: libraries from
# HaikuPorts are cross-built by build-deps.sh and linked in statically. Then set
# HPKG_REQUIRES_ARM64 in haiku-app.env (usually "") to say so; it lists anything the arm64
# package still requires besides haiku (e.g. an architecture "any" data package).
# Same package as build-hpkg.sh, except: Haiku's host `package` tool builds it, and the
# host mimeset can't read arm64 binaries (it would set BEOS:TYPE to
# application/octet-stream), so the type and signature are written with the host addattr.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
. ./haiku-app.env

ARCH=arm64
OUT="$ROOT/${APP_CMD}-${VERSION}-${REVISION}-${ARCH}.hpkg"

[ -n "${HAIKU_CROSS_CFLAGS:-}" ] || {
	echo "build-hpkg-arm64: source the env.sh from tools/haiku-arm64/make-sysroot.sh first" >&2; exit 1; }
for tool in aarch64-unknown-haiku-g++ rc xres package addattr; do
	command -v "$tool" >/dev/null 2>&1 || { echo "build-hpkg-arm64: '$tool' not found" >&2; exit 1; }
done
if [ -n "${HPKG_REQUIRES_EXTRA:-}" ] && [ -z "${HPKG_REQUIRES_ARM64+set}" ]; then
	echo "build-hpkg-arm64: HPKG_REQUIRES_EXTRA is set ($HPKG_REQUIRES_EXTRA), but HaikuPorts has" \
		"no arm64 packages: link them in (tools/haiku-arm64/build-deps.sh) and set" \
		"HPKG_REQUIRES_ARM64 in haiku-app.env" >&2
	exit 1
fi

# 1. Build, stripped at link time (xres appends the resources after the ELF data)
make clean >/dev/null
make HAIKU_CROSS=1 LDFLAGS="${LDFLAGS:-} -s"
BINS="$APP_NAME"
for pair in ${HPKG_EXTRA_FILES:-}; do BINS="$BINS ${pair%%:*}"; done
for bin in $BINS; do
	[ "$(head -c4 "$bin" | od -An -c | tr -d ' ')" = '177ELF' ] || continue
	case "$(od -An -tx1 -j18 -N1 "$bin" | tr -d ' ')" in
		b7) ;;
		*) echo "build-hpkg-arm64: $bin is not an aarch64 binary" >&2; exit 1 ;;
	esac
done

# 2. Package tree, relative to the install location (/boot/system)
PKG="$ROOT/obj/hpkg-$ARCH"
rm -rf "$PKG"
mkdir -p "$PKG/apps" "$PKG/bin" "$PKG/data/deskbar/menu/Applications" \
	"$PKG/documentation/packages/$APP_CMD"
cp "$APP_NAME" "$PKG/apps/$APP_NAME"
addattr -t mime BEOS:TYPE application/x-vnd.Be-elfexecutable "$PKG/apps/$APP_NAME"
addattr -t mime BEOS:APP_SIG "$APP_SIG" "$PKG/apps/$APP_NAME"
ln -s "../apps/$APP_NAME" "$PKG/bin/$APP_CMD"
ln -s "../../../../apps/$APP_NAME" \
	"$PKG/data/deskbar/menu/Applications/${DESKBAR_NAME:-$APP_NAME}"
cp README.md LICENSE "$PKG/documentation/packages/$APP_CMD/" 2>/dev/null || :
for pair in ${HPKG_EXTRA_FILES:-}; do
	from=${pair%%:*}; to=${pair#*:}
	mkdir -p "$PKG/$(dirname "$to")"
	cp "$from" "$PKG/$to"
done

# 3. .PackageInfo: haiku >= r1~beta6 is satisfied by the arm64 nightlies
#    (r1~beta6_hrevNNNNN) and keeps the file the same as the x86_64 one
DESC=$(sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e '2,$s/^/\t/' "$DESCRIPTION_FILE")
REQ=""
for r in ${HPKG_REQUIRES_ARM64:-}; do REQ="$REQ
	$r"; done
REPLACES=""
if [ -n "${HPKG_REPLACES:-}" ]; then
	REPLACES="replaces		{"
	for r in $HPKG_REPLACES; do REPLACES="$REPLACES
	$r"; done
	REPLACES="$REPLACES
}"
fi
cat > "$PKG/.PackageInfo" <<INFO
name			$APP_CMD
version			$VERSION-$REVISION
architecture	$ARCH
summary			"$SUMMARY"
description		"$DESC"
packager		"$PACKAGER"
vendor			"$APP_NAME"
copyrights		{
	"$COPYRIGHT"
}
licenses		{
	"$LICENSE_NAME"
}
urls			{
	"$HOMEPAGE"
}
provides		{
	$APP_CMD = $VERSION
	app:$APP_NAME = $VERSION
	cmd:$APP_CMD
}
requires		{
	haiku >= r1~beta6$REQ
}
$REPLACES
INFO

# 4. Package
rm -f "$OUT"
package create -C "$PKG" "$OUT"
package list -i "$OUT" >/dev/null
# The arm64 objects would otherwise be picked up by a native build or `make test`
make clean >/dev/null
echo "Built $OUT"
