# tree - directory listing
deps=""
provides="tree"

build() {
	make -j"$JOBS" CC="$CC" CFLAGS="$CFLAGS -DLINUX -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64" \
		LDFLAGS="$LDFLAGS"
	put_bin tree
	put_license LICENSE
}
