# zstd - lib for adb/fastboot, plus the cli
deps=""
provides="zstd"

build() {
	make -C lib -j"$JOBS" libzstd.a
	make -C lib install-static install-includes install-pc PREFIX="$PREFIX" >/dev/null
	make -C programs -j"$JOBS" zstd HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0
	put_bin programs/zstd
	put_license LICENSE COPYING
}
