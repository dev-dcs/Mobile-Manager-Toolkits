# erofs-utils - mkfs.erofs, fsck.erofs (--extract unpacks an image), dump.erofs
deps="e2fsprogs zlib xz lz4 zstd"
provides="mkfs.erofs fsck.erofs dump.erofs"

build() {
	./autogen.sh >/dev/null 2>&1 || autoreconf -fi
	auto_build --enable-lz4 --enable-lzma --with-zlib --with-libzstd --with-uuid \
		--without-selinux --disable-fuse --without-libdeflate --without-qpl \
		--without-xxhash --without-libcurl --without-openssl --without-libxml2 \
		--without-json --without-libnl3 --disable-werror
	put_bin "$BLD/mkfs/mkfs.erofs"
	put_bin "$BLD/fsck/fsck.erofs"
	put_bin "$BLD/dump/dump.erofs"
	put_license COPYING LICENSES/GPL-2.0 LICENSES/Apache-2.0
}
