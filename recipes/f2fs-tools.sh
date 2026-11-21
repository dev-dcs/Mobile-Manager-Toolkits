# f2fs-tools - dump.f2fs (pull files out of an f2fs image) and resize.f2fs.
# one binary that picks its job from argv[0]; Android has fsck.f2fs and make_f2fs
deps="e2fsprogs"
provides="dump.f2fs resize.f2fs"

build() {
	./autogen.sh >/dev/null 2>&1 || autoreconf -fi
	mkdir -p "$BLD"
	# major()/minor() live in sys/sysmacros.h on musl, libf2fs never includes it
	(cd "$BLD" && CPPFLAGS="$CPPFLAGS -include sys/sysmacros.h" \
		"$SRC/configure" --host="$TARGET_TRIPLE" --prefix="$PREFIX" \
		--enable-static --disable-shared --without-selinux --without-blkid)
	# only lib + fsck, tools/ wants BSD sys/queue.h
	make -C "$BLD/lib" -j"$JOBS"
	make -C "$BLD/fsck" -j"$JOBS"
	put_bin "$BLD/fsck/fsck.f2fs" dump.f2fs
	put_bin "$BLD/fsck/fsck.f2fs" resize.f2fs
	put_license COPYING
}
