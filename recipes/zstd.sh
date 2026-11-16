# zstd - lib only, adb/fastboot want it
deps=""

build() {
	make -C lib -j"$JOBS" libzstd.a
	make -C lib install-static install-includes install-pc PREFIX="$PREFIX" >/dev/null
}
