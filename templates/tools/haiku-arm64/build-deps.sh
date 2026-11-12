#!/bin/sh
# build-deps.sh — cross-builds, statically, the HaikuPorts libraries an app needs on Haiku
# arm64, where HaikuPorts has no repository yet. zlib and OpenSSL are here; add the app's
# own libraries at the end with the cmake_lib / autotools_lib helpers. The app links them
# in, so its arm64 .hpkg requires only haiku.
#
#   sh tools/haiku-arm64/make-sysroot.sh ~/.cache/haiku-arm64    (once)
#   . ~/.cache/haiku-arm64/env.sh
#   sh tools/haiku-arm64/build-deps.sh
#   make HAIKU_CROSS=1    (Makefile: -I$(HAIKU_ARM64)/deps/include -L$(HAIKU_ARM64)/deps/lib)
#
# Use the versions, checksums and Haiku patches of HaikuPorts' x86_64 packages (their
# recipes and patchsets are fetched from haikuports/haikuports). Installs into
# $HAIKU_ARM64/deps. Example of a larger library built this way: TDLib (Powergram's
# tools/haiku-arm64/build-deps.sh), which first generates its sources with a native build.
set -eu
[ -n "${HAIKU_ARM64:-}" ] || { echo "build-deps: source env.sh from make-sysroot.sh first" >&2; exit 1; }
W=$HAIKU_ARM64
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$W/src; B=$W/build; DEPS=$W/deps
JOBS=$(nproc 2>/dev/null || echo 4)
export TMPDIR=${TMPDIR:-$W/tmp}; mkdir -p "$TMPDIR" "$SRC/recipes" "$B" "$DEPS"
TARGET=aarch64-unknown-haiku
HP=https://raw.githubusercontent.com/haikuports/haikuports/master
say() { printf '\n== %s\n' "$*"; }

fetch() {   # url file sha256
	[ -s "$SRC/$2" ] || curl -fsSL -o "$SRC/$2" "$1"
	echo "$3  $SRC/$2" | sha256sum -c --quiet
}
patchset() {   # path in haikuports, e.g. dev-libs/openssl/patches/openssl3-3.5.9.patchset
	[ -s "$SRC/recipes/${1##*/}" ] || curl -fsSL -o "$SRC/recipes/${1##*/}" "$HP/$1"
}
unpack() {  # archive dir [patchset]
	rm -rf "$B/$2"; mkdir -p "$B/$2"
	tar xf "$SRC/$1" -C "$B/$2" --strip-components=1
	[ -z "${3:-}" ] || ( cd "$B/$2" && patch -p1 -s < "$SRC/recipes/$3" )
}
CFLAGS_X="$HAIKU_CROSS_CFLAGS -O2 -fPIC"
LDFLAGS_X="$HAIKU_CROSS_LDFLAGS"

# A CMake toolchain file for the app's own CMake libraries
cat > "$B/haiku-arm64.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Haiku)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER $(command -v "$CC"))
set(CMAKE_CXX_COMPILER $(command -v "$CXX"))
set(CMAKE_SYSROOT $HAIKU_ARM64_SYSROOT)
set(CMAKE_C_FLAGS_INIT "$HAIKU_CROSS_CFLAGS")
set(CMAKE_CXX_FLAGS_INIT "$HAIKU_CROSS_CFLAGS")
set(CMAKE_EXE_LINKER_FLAGS_INIT "$HAIKU_CROSS_LDFLAGS -lnetwork")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "$HAIKU_CROSS_LDFLAGS -lnetwork")
set(CMAKE_FIND_ROOT_PATH $DEPS $HAIKU_ARM64_SYSROOT $HAIKU_ARM64_SYSROOT/develop)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
cmake_lib() {   # dir [cmake options...]
	d=$1; shift
	( cd "$B/$d" && cmake -B build-arm64 -S . -DCMAKE_TOOLCHAIN_FILE="$B/haiku-arm64.cmake" \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS" -DBUILD_SHARED_LIBS=OFF \
		-DOPENSSL_ROOT_DIR="$DEPS" -DOPENSSL_USE_STATIC_LIBS=TRUE \
		-DZLIB_ROOT="$DEPS" -DZLIB_USE_STATIC_LIBS=ON "$@" > "$B/$d-cmake.log" 2>&1 \
		&& cmake --build build-arm64 -j"$JOBS" > "$B/$d-build.log" 2>&1 \
		&& cmake --install build-arm64 > /dev/null ) \
		|| { tail -30 "$B/$d-cmake.log" "$B/$d-build.log" 2>/dev/null; exit 1; }
}
autotools_lib() {   # dir [configure options...]
	d=$1; shift
	( cd "$B/$d" && ./configure --host=$TARGET --prefix="$DEPS" --disable-shared \
		CC=$CC CXX=$CXX CFLAGS="$CFLAGS_X" CXXFLAGS="$CFLAGS_X" LDFLAGS="$LDFLAGS_X" "$@" \
		> "$B/$d-configure.log" 2>&1 && make -j"$JOBS" install > "$B/$d-build.log" 2>&1 ) \
		|| { tail -30 "$B/$d-configure.log" "$B/$d-build.log" 2>/dev/null; exit 1; }
}

say zlib
fetch https://zlib.net/fossils/zlib-1.3.1.tar.gz zlib.tar.gz \
	9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
unpack zlib.tar.gz zlib
( cd "$B/zlib" && CC=$CC CFLAGS="$CFLAGS_X" LDFLAGS="$LDFLAGS_X" CHOST=$TARGET \
	./configure --static --prefix="$DEPS" > /dev/null && make -j"$JOBS" install > /dev/null )

if [ "${WITH_OPENSSL:-1}" = 1 ]; then
	say OpenSSL
	fetch https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz \
		openssl.tar.gz 603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
	patchset dev-libs/openssl/patches/openssl3-3.5.9.patchset
	unpack openssl.tar.gz openssl openssl3-3.5.9.patchset
	# Ours as well: no SIGILL feature probing, which panics Haiku arm64's kernel (the SVE
	# probe traps as exception class 25 instead of raising SIGILL)
	( cd "$B/openssl" && patch -p1 -s < "$HERE/openssl-haiku-arm64.patch" )
	mkdir -p "$B/openssl-conf"
	# Haiku's targets add "-include os-dep/haiku.h", a C header, to every compile; on
	# aarch64 the assembly is preprocessed too, so this target guards it
	cat > "$B/openssl-conf/haiku-aarch64.h" <<'EOF'
#ifndef __ASSEMBLER__
#include <sys/select.h>
#include <sys/time.h>
#endif
EOF
	cat > "$B/openssl-conf/60-haiku-aarch64.conf" <<EOF
my %targets = (
    "haiku-aarch64" => {
        inherit_from     => [ "BASE_unix" ],
        CFLAGS           => picker(default => "-Wall", release => "-O2"),
        cflags           => add_before("-DL_ENDIAN -include $B/openssl-conf/haiku-aarch64.h",
                                       threads("-D_REENTRANT")),
        HASHBANGPERL     => "/bin/env perl",
        sys_id           => "HAIKU",
        ex_libs          => add("-lnetwork"),
        thread_scheme    => "pthreads",
        dso_scheme       => "dlfcn",
        bn_ops           => "SIXTY_FOUR_BIT_LONG RC4_CHAR",
        asm_arch         => 'aarch64',
        perlasm_scheme   => "linux64",
    },
);
EOF
	# The certificates where Haiku keeps them, as HaikuPorts' openssl3 does
	( cd "$B/openssl" && OPENSSL_LOCAL_CONFIG_DIR="$B/openssl-conf" CC=$CC \
		./Configure haiku-aarch64 --prefix="$DEPS" --libdir=lib --openssldir=/boot/system/data/ssl \
		no-shared no-tests no-apps no-docs no-module enable-zlib \
		--with-zlib-include="$DEPS/include" --with-zlib-lib="$DEPS/lib" \
		$HAIKU_CROSS_CFLAGS $HAIKU_CROSS_LDFLAGS > "$B/openssl-configure.log" \
		&& make -j"$JOBS" > "$B/openssl-build.log" 2>&1 && make install_sw > /dev/null ) \
		|| { tail -20 "$B/openssl-build.log" 2>/dev/null; exit 1; }
fi

# ── The app's own libraries ──
# fetch <url> <name>.tar.gz <sha256>; patchset <haikuports path>; unpack <name>.tar.gz <dir> [patchset]
# then cmake_lib <dir> [-DOPTION=...] or autotools_lib <dir> [--option...]

ls "$DEPS/lib"/*.a | sed 's|.*/||' | tr '\n' ' '; echo
say "done: $DEPS"
