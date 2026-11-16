# zlib - static only
deps=""

build() {
	CHOST=$TARGET_TRIPLE ./configure --static --prefix="$PREFIX" >/dev/null
	make -j"$JOBS" libz.a
	make install >/dev/null
}
