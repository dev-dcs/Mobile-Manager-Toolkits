# squashfs-tools - mksquashfs / unsquashfs
deps="zlib xz lz4 zstd"
provides="mksquashfs unsquashfs"

build() {
	make -C squashfs-tools -j"$JOBS" CC="$CC" EXTRA_CFLAGS="$CFLAGS" EXTRA_LDFLAGS="$LDFLAGS" \
		GZIP_SUPPORT=1 XZ_SUPPORT=1 LZ4_SUPPORT=1 ZSTD_SUPPORT=1 LZO_SUPPORT=0 \
		mksquashfs unsquashfs
	put_bin squashfs-tools/mksquashfs
	put_bin squashfs-tools/unsquashfs
	put_license COPYING
}
