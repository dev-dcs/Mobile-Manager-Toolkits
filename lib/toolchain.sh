# shellcheck shell=bash
# zig standing in for the cross compiler. static musl, aarch64 for now. @Dev_DcS
#
# newer phones ship 16k page kernels now, so every link gets
# -z max-page-size=16384. 16k alignment is also a multiple of 4k so the old
# phones are happy too. build.sh double-checks each binary afterwards.

TARGET_ARCH=aarch64
TARGET_TRIPLE=aarch64-linux-musl
TARGET_CPU=baseline
PAGE_ALIGN=16384
RUST_TARGET=aarch64-unknown-linux-musl

find_zig() {
	if have zig; then
		ZIG=$(command -v zig)
	elif python3 -c 'import ziglang' 2>/dev/null; then
		ZIG=$(python3 -c 'import ziglang, os; print(os.path.join(os.path.dirname(ziglang.__file__), "zig"))')
	else
		die "zig not found (pip install ziglang==0.17.1, or put zig in PATH)"
	fi
}

setup_toolchain() {
	local tc="$WORK/tc" t
	find_zig
	mkdir -p "$tc"
	export ZIG_GLOBAL_CACHE_DIR="$WORK/zig-cache" ZIG_LOCAL_CACHE_DIR="$WORK/zig-cache"

	for t in cc c++; do
		cat > "$tc/$TARGET_ARCH-$t" <<-EOF
		#!/bin/sh
		# strip flags zig doesn't grok, tack the page size onto link steps
		link=1
		for a; do
		    shift
		    case \$a in
		        -c|-S|-E|-M|-MM) link=0; set -- "\$@" "\$a" ;;
		        -Wl,-z,separate-loadable-segments|-Wl,--compress-debug-sections=*|-Wl,--no-undefined-version) ;;
		        *) set -- "\$@" "\$a" ;;
		    esac
		done
		[ \$link = 1 ] && set -- "\$@" -Wl,-z,max-page-size=$PAGE_ALIGN
		# no -mcpu: baseline is zig's default anyway, and passing it explicitly
		# blows up meson's "cc -E" compiler probe (baseline isn't a clang cpu)
		exec "$ZIG" $t -target $TARGET_TRIPLE "\$@"
		EOF
	done
	for t in ar ranlib; do
		printf '#!/bin/sh\nexec "%s" %s "$@"\n' "$ZIG" "$t" > "$tc/$TARGET_ARCH-$t"
	done
	chmod +x "$tc"/*

	STRIP=$(command -v llvm-strip || true)
	[ -n "$STRIP" ] || STRIP=$(compgen -c llvm-strip- | sort -V | tail -1 || true)
	[ -n "$STRIP" ] || die "llvm-strip is needed to strip aarch64 binaries"

	PREFIX="$WORK/prefix"
	HOSTP="$WORK/host"
	mkdir -p "$PREFIX/lib/pkgconfig" "$PREFIX/include" "$HOSTP/bin"

	export CC="$tc/$TARGET_ARCH-cc" CXX="$tc/$TARGET_ARCH-c++"
	export AR="$tc/$TARGET_ARCH-ar" RANLIB="$tc/$TARGET_ARCH-ranlib"
	# -fPIC on everything. android binaries are PIE and lld chokes on
	# R_AARCH64_ABS64 against local syms otherwise (cryptopp + lz4 both bit me)
	export CFLAGS="-O2 -fPIC -ffunction-sections -fdata-sections -I$PREFIX/include"
	export CXXFLAGS="$CFLAGS"
	export CPPFLAGS="-I$PREFIX/include"
	export LDFLAGS="-static -Wl,--gc-sections -L$PREFIX/lib"
	export PKG_CONFIG="pkg-config --static"
	export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
	export PKG_CONFIG_PATH=""
	export PATH="$HOSTP/bin:$PATH"

	CMAKE_TC="$tc/$TARGET_ARCH.cmake"
	cat > "$CMAKE_TC" <<-EOF
	set(CMAKE_SYSTEM_NAME Linux)
	set(CMAKE_SYSTEM_PROCESSOR $TARGET_ARCH)
	set(CMAKE_C_COMPILER $CC)
	set(CMAKE_CXX_COMPILER $CXX)
	set(CMAKE_AR $AR CACHE FILEPATH "" FORCE)
	set(CMAKE_RANLIB $RANLIB CACHE FILEPATH "" FORCE)
	set(CMAKE_FIND_ROOT_PATH $PREFIX)
	set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
	set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
	set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
	set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
	set(CMAKE_EXE_LINKER_FLAGS_INIT "-static -Wl,--gc-sections")
	set(PKG_CONFIG_ARGN --static)
	EOF

	MESON_CROSS="$tc/$TARGET_ARCH.meson"
	cat > "$MESON_CROSS" <<-EOF
	[binaries]
	c = '$CC'
	cpp = '$CXX'
	ar = '$AR'
	strip = '$STRIP'
	pkg-config = ['pkg-config', '--static']

	[host_machine]
	system = 'linux'
	cpu_family = 'aarch64'
	cpu = 'aarch64'
	endian = 'little'

	[properties]
	pkg_config_libdir = '$PREFIX/lib/pkgconfig'

	[built-in options]
	default_library = 'static'
	prefer_static = true
	c_link_args = ['-static']
	cpp_link_args = ['-static']
	EOF

	TC_ID="zig-$("$ZIG" version) $TARGET_TRIPLE $TARGET_CPU page=$PAGE_ALIGN"
	export CMAKE_TC MESON_CROSS PREFIX HOSTP STRIP TC_ID
}

# helpers recipes use

cmake_build() {
	cmake -S "${CM_SRC:-.}" -B "$BLD" -G Ninja \
		-DCMAKE_TOOLCHAIN_FILE="$CMAKE_TC" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_PREFIX_PATH="$PREFIX" \
		-DBUILD_SHARED_LIBS=OFF \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		"$@"
	ninja -C "$BLD" -j "$JOBS"
}

cmake_install() { ninja -C "$BLD" install >/dev/null; }

auto_build() {
	[ -x ./configure ] || autoreconf -fi
	mkdir -p "$BLD"
	(cd "$BLD" && "$SRC/configure" --host="$TARGET_TRIPLE" --prefix="$PREFIX" \
		--enable-static --disable-shared "$@")
	make -C "$BLD" -j "$JOBS"
}

meson_build() {
	# CC_LD=lld: tell meson the linker outright. zig's linker reports itself as
	# "zig ld" which older meson (<1.8, e.g. ubuntu's 1.3) can't classify and
	# bails on. zig uses lld under the hood so this is honest, and newer meson
	# doesn't mind.
	CC_LD=lld CXX_LD=lld \
		meson setup "$BLD" --cross-file "$MESON_CROSS" --prefix "$PREFIX" \
		--buildtype release --default-library static "$@"
	ninja -C "$BLD" -j "$JOBS"
}

# cargo_build [extra cargo args] - build a Rust crate static for aarch64 via
# cargo-zigbuild (reuses our zig). Binaries land in $CARGO_OUT.
cargo_build() {
	have cargo || die "rust toolchain missing (rustup) for a cargo recipe"
	have cargo-zigbuild || python3 -m pip show cargo-zigbuild >/dev/null 2>&1 ||
		die "cargo-zigbuild missing (pip install cargo-zigbuild)"
	rustup target list --installed 2>/dev/null | grep -qx "$RUST_TARGET" ||
		rustup target add "$RUST_TARGET" >/dev/null 2>&1 || die "cannot add rust target $RUST_TARGET"
	export CARGO_HOME="${CARGO_HOME:-$WORK/cargo}"
	CARGO_OUT="$SRC/target/$RUST_TARGET/release"
	# leave CC_<triple> alone. cargo-zigbuild drops in its own zigcc for cc-rs
	# crates like ring and gets the triple right; our wrapper would double up
	# the --target and blow up. just hand it the page size.
	RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-z,max-page-size=$PAGE_ALIGN" \
		cargo zigbuild --release --target "$RUST_TARGET" "$@"
}

# put_bin <file> [name] - ship a binary
put_bin() {
	mkdir -p "$OUT/bin"
	install -m 755 "$1" "$OUT/bin/${2:-${1##*/}}"
}

# put_asset <file> <dest-relative-path> - ship a non-binary file (payload blob,
# data) under the module's share/ tree
put_asset() {
	mkdir -p "$OUT/asset/$(dirname "$2")"
	cp -a "$1" "$OUT/asset/$2"
}

# put_system <src> <dest-under-system> - drop a file or directory straight into
# the module's system/ overlay (e.g. etc/terminfo for nano). Unlike put_bin the
# contents are copied verbatim and never run through the ELF check/strip pass.
put_system() {
	mkdir -p "$OUT/system/$(dirname "$2")"
	cp -a "$1" "$OUT/system/$2"
}

# put_license <file>... - goes to licenses/<component>/ in the zip
put_license() {
	local f
	mkdir -p "$OUT/license"
	for f; do [ -f "$f" ] && cp "$f" "$OUT/license/"; done
	return 0
}
