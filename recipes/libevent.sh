# libevent - for tmux
deps=""

build() {
	auto_build --disable-openssl --disable-mbedtls --disable-samples \
		--disable-libevent-regress --disable-debug-mode
	make -C "$BLD" install >/dev/null
}
