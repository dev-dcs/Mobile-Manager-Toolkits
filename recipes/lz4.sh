# lz4 lib + cli (Samsung firmware ships *.img.lz4)
deps=""
provides="lz4"

build() {
	make -C lib -j"$JOBS" liblz4.a
	make -C lib install BUILD_SHARED=no PREFIX="$PREFIX" >/dev/null
	make -C programs -j"$JOBS" lz4
	put_bin programs/lz4
	put_license LICENSE lib/LICENSE programs/COPYING
}
