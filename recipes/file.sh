# file - tells what a file is
# the magic database has to be compiled by a file of the same version, so the
# host build makes it. same endianness, so the arm binary reads it as is.
deps=""
provides="file"

# shellcheck disable=SC2086
build() {
	local off="--disable-zlib --disable-bzlib --disable-xzlib --disable-zstdlib --disable-lzlib --disable-libseccomp"
	mkdir -p "$BLD/host"
	(cd "$BLD/host" &&
		env -u CPPFLAGS -u LDFLAGS -u PKG_CONFIG_LIBDIR CC=gcc CFLAGS=-O2 \
		"$SRC/configure" --disable-shared $off >/dev/null &&
		make -j"$JOBS" >/dev/null)
	mkdir -p "$BLD/arm"
	(cd "$BLD/arm" && "$SRC/configure" --host="$TARGET_TRIPLE" --prefix="$PREFIX" \
		--enable-static --disable-shared $off)
	make -C "$BLD/arm/src" -j"$JOBS" MAGIC=/system/etc/magic
	put_bin "$BLD/arm/src/file"
	put_system "$BLD/host/magic/magic.mgc" etc/magic.mgc
	put_license COPYING
}
