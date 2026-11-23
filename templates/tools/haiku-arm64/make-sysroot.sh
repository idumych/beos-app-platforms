#!/bin/sh
# make-sysroot.sh — builds what an app needs to be compiled on Linux for Renku OS arm64:
# the cross toolchain (gcc 13 for aarch64-unknown-haiku), the host tools (package, rc, xres,
# addattr, bfs_shell) and a sysroot made from Renku's arm64 packages.
#
#   sh tools/haiku-arm64/make-sysroot.sh [WORK_DIR]        (default ./.haiku-arm64)
#   . WORK_DIR/env.sh && make HAIKU_CROSS=1 && sh packaging/build-hpkg-arm64.sh
#
# Runs on an x86_64 Linux host with a C/C++ toolchain, git, curl, flex, bison,
# texinfo (makeinfo), zlib and zstd headers. Takes about 20 minutes; the result is about
# 3 GB and can be cached (CI) or kept between releases.
#
# Where the pieces come from (all Renku, since arm64 builds target Renku OS, not Haiku):
#  - Renku's arm64 system repository has haiku and haiku_devel: libroot, libbe, libtracker,
#    libtranslation, the CRT objects and the headers.
#  - libbe needs libstdc++, libgcc_s, ICU and zlib: gcc_syslibs, icu74 and zlib from Renku's
#    arm64 ports repository (RenkuOSPorts).
#  - The toolchain and host tools are built from RenkuOS/Source with Haiku's buildtools.
# These repositories are for Renku OS only: the packages built here are tested on Renku
# arm64, and the repositories are never added to a Haiku system.
# None of this is sent anywhere: only public downloads.
set -eu

WORK=$(mkdir -p "${1:-.haiku-arm64}" && cd "${1:-.haiku-arm64}" && pwd)
JOBS=$(nproc 2>/dev/null || echo 4)
REPO=https://renkuos.freemyip.com/repo/arm64
PORTS=https://renkuos.freemyip.com/repo/renkuosports/arm64
say() { printf '\n== %s\n' "$*"; }

# 1. Which Renku build the arm64 repository is at (its page lists the packages)
say "Renku arm64 repository"
VERSION=$(curl -fsSL "$REPO/" | grep -oE 'haiku-r1~[a-z0-9]+_hrev[0-9]+_[0-9]+-1-arm64\.hpkg' | head -1 \
	| sed -E 's/^haiku-(.*)-1-arm64\.hpkg$/\1/')
[ -n "$VERSION" ] || { echo "make-sysroot: can't read the package list at $REPO/" >&2; exit 1; }
echo "$VERSION"
if [ -f "$WORK/sysroot/.version" ] && [ "$(cat "$WORK/sysroot/.version")" = "$VERSION" ]; then
	echo "sysroot for $VERSION is already there"; exit 0
fi

# 2. Sources: RenkuOS/Source (the system the packages come from) and Haiku's buildtools
say "Sources"
[ -d "$WORK/haiku/.git" ] || git clone -q --depth 1 https://github.com/RenkuOS/Source "$WORK/haiku"
[ -d "$WORK/buildtools/.git" ] || git clone -q --depth 1 \
	https://review.haiku-os.org/buildtools "$WORK/buildtools"

# 3. Cross toolchain. configure insists on an ELF-capable nasm even for arm64, where it is
#    never used; a stand-in answers its format query.
mkdir -p "$WORK/bin" "$WORK/generated"
cat > "$WORK/bin/nasm-stub" <<'EOF'
#!/bin/sh
# configure only asks nasm for its ELF formats; arm64 builds never run it
printf '  elf32 \n  elf64 \n'
EOF
chmod +x "$WORK/bin/nasm-stub"
CROSS="$WORK/generated/cross-tools-arm64/bin/aarch64-unknown-haiku-g++"
if [ ! -x "$CROSS" ]; then
	say "Cross toolchain (about 15 minutes)"
	( cd "$WORK/generated" && HAIKU_NASM="$WORK/bin/nasm-stub" ../haiku/configure \
		--cross-tools-source ../buildtools --build-cross-tools arm64 -j"$JOBS" )
elif [ ! -f "$WORK/generated/build/BuildConfig" ]; then
	# A compiler copied in from an earlier build (haiku-arm64.md: flex): configure around it
	say "Configuring with the existing cross toolchain"
	( cd "$WORK/generated" && HAIKU_NASM="$WORK/bin/nasm-stub" ../haiku/configure \
		--cross-tools-prefix "$WORK/generated/cross-tools-arm64/bin/aarch64-unknown-haiku-" )
fi

# 4. jam, then Haiku's host tools
say "Host tools"
JAM=$(ls "$WORK"/buildtools/jam/bin.*/jam 2>/dev/null | head -1)
if [ -z "$JAM" ]; then
	make -C "$WORK/buildtools/jam" -j"$JOBS" > /dev/null
	JAM=$(ls "$WORK"/buildtools/jam/bin.*/jam | head -1)
fi
( cd "$WORK/generated" && "$JAM" -q -j"$JOBS" '<build>package' '<build>rc' '<build>xres' \
	'<build>addattr' '<build>bfs_shell' > "$WORK/host-tools.log" 2>&1 ) \
	|| { tail -20 "$WORK/host-tools.log"; exit 1; }
T=$(find "$WORK/generated/objects" -type d -path '*/release/tools' | head -1)
# Only these go on PATH: Haiku's host mimeset doesn't recognise arm64 binaries (it would set
# BEOS:TYPE to application/octet-stream), so it is left out
for t in package/package rc/rc xres addattr/addattr bfs_shell/bfs_shell; do
	ln -sf "$T/$t" "$WORK/bin/$(basename "$t")"
done

# 5. Packages: haiku and haiku_devel from Renku's system repository, the runtime libraries
#    libbe links against from Renku's ports repository
say "Packages"
P="$WORK/packages"
mkdir -p "$P"
for pkg in haiku haiku_devel; do
	f="$pkg-$VERSION-1-arm64.hpkg"
	[ -s "$P/$f" ] || curl -fsSL -o "$P/$f" "$REPO/packages/$f"
done
PORTLIST=$(curl -fsSL "$PORTS/" | grep -oE 'packages/[^"]+\.hpkg' | sed 's|packages/||')
LIST=""
# Ports the app links against besides those (HPKG_ARM64_PORTS in haiku-app.env, e.g.
# "curl curl_devel"), so they're in the sysroot too
APP_PORTS=$( [ -f ./haiku-app.env ] && . ./haiku-app.env && echo "${HPKG_ARM64_PORTS:-}" || : )
for name in gcc_syslibs 'icu[0-9]+' zlib $APP_PORTS; do
	f=$(echo "$PORTLIST" | grep -E "^$name-[0-9][^-]*-[0-9]+-arm64\.hpkg$" | sort -V | tail -1)
	[ -n "$f" ] || { echo "make-sysroot: no $name package in $PORTS/" >&2; exit 1; }
	[ -s "$P/$f" ] || curl -fsSL -o "$P/$f" "$PORTS/packages/$f"
	LIST="$LIST $f"
done
echo "$LIST"

# 6. Sysroot: the packages extracted as they'd be under /boot/system
say "Sysroot"
rm -rf "$WORK/sysroot"
mkdir -p "$WORK/sysroot"
for f in "$P"/haiku-"$VERSION"-1-arm64.hpkg "$P"/haiku_devel-"$VERSION"-1-arm64.hpkg; do
	"$WORK/bin/package" extract -C "$WORK/sysroot" "$f"
done
for f in $LIST; do "$WORK/bin/package" extract -C "$WORK/sysroot" "$P/$f"; done
echo "$VERSION" > "$WORK/sysroot/.version"

# 7. env.sh. Kit headers go first (-I); the C library headers come after the compiler's own
#    C++ headers (-idirafter), as Haiku's native compiler orders them, or libstdc++'s
#    #include_next <stdlib.h> fails. bsd and gnu go before posix: posix/features.h is an
#    empty stand-in, and bsd/features.h must win to define _DEFAULT_SOURCE (NI_MAXHOST,
#    h_errno...).
cat > "$WORK/env.sh" <<EOF
# source me: . $WORK/env.sh   — Renku OS arm64 cross build ($VERSION)
export HAIKU_ARM64="$WORK"
export PATH="\$HAIKU_ARM64/generated/cross-tools-arm64/bin:\$HAIKU_ARM64/bin:\$PATH"
export HAIKU_ARM64_SYSROOT="\$HAIKU_ARM64/sysroot"
export HAIKU_ARM64_VERSION="$VERSION"
_s=\$HAIKU_ARM64_SYSROOT/develop/headers
_inc=""
for _d in \$(find \$_s/os -mindepth 1 -type d) \$_s/os \$_s/be_apps/Tracker; do _inc="\$_inc -I\$_d"; done
for _d in \$_s/bsd \$_s/gnu \$_s/posix \$_s; do _inc="\$_inc -idirafter \$_d"; done
export CC=aarch64-unknown-haiku-gcc CXX=aarch64-unknown-haiku-g++
export HAIKU_CROSS_CFLAGS="--sysroot=\$HAIKU_ARM64_SYSROOT\$_inc"
export HAIKU_CROSS_LDFLAGS="--sysroot=\$HAIKU_ARM64_SYSROOT -B\$HAIKU_ARM64_SYSROOT/develop/lib -L\$HAIKU_ARM64_SYSROOT/develop/lib -L\$HAIKU_ARM64_SYSROOT/lib -Wl,-rpath-link=\$HAIKU_ARM64_SYSROOT/lib"
unset _s _inc _d
EOF
say "done: $VERSION"
echo "Use it with:   . $WORK/env.sh && make HAIKU_CROSS=1 && sh packaging/build-hpkg-arm64.sh"
