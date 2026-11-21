# e2fsprogs - debugfs and dumpe2fs. Android already has e2fsck/mke2fs/resize2fs/tune2fs.
# also installs libuuid for f2fs-tools and erofs-utils
deps=""
provides="debugfs dumpe2fs"

build() {
	mkdir -p "$BLD"
	(cd "$BLD" && "$SRC/configure" --host="$TARGET_TRIPLE" --prefix="$PREFIX" \
		--disable-nls --disable-fuse2fs --disable-uuidd --disable-fsck \
		--disable-e2initrd-helper --disable-elf-shlibs --enable-libuuid --enable-libblkid \
		--with-crond-dir=no --with-systemd-unit-dir=no --with-udev-rules-dir=no)
	make -C "$BLD" -j"$JOBS" libs
	make -C "$BLD/debugfs" -j"$JOBS" debugfs
	make -C "$BLD/misc" -j"$JOBS" dumpe2fs
	make -C "$BLD/lib/uuid" install >/dev/null
	put_bin "$BLD/debugfs/debugfs"
	put_bin "$BLD/misc/dumpe2fs"
	put_license NOTICE
}
