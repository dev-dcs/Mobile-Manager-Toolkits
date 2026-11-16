# openssl - static libcrypto/libssl for the iOS tools (img4tool, futurerestore)
deps=""
provides=""

build() {
	# openssl's own Configure; linux-aarch64 target, no asm to stay portable
	CC="$CC" AR="$AR" RANLIB="$RANLIB" \
	./Configure linux-aarch64 no-shared no-tests no-docs no-apps no-asm \
		--prefix="$PREFIX" --openssldir="$PREFIX/ssl" \
		-static >/dev/null
	make -j"$JOBS" build_libs >/dev/null
	make install_dev >/dev/null
}
