# strace - syscall tracer
# zig's kernel headers trail new strace releases (FD_FAILFS_ROOT and friends).
# strace ships the newer ones under bundled/, but clang treats that path as a
# system dir behind zig's own. a copy under another path, passed with -I, wins.
deps=""
provides="strace"

build() {
	mkdir -p "$BLD/uapi"
	cp -a bundled/linux/include/uapi/. "$BLD/uapi/"
	cp -a bundled/linux/arch/arm64/include/uapi/. "$BLD/uapi/"
	CPPFLAGS="-I$BLD/uapi $CPPFLAGS" \
		auto_build --enable-bundled=yes --enable-mpers=no \
		--without-libunwind --without-libdw --without-libselinux
	put_bin "$BLD/src/strace"
	put_license COPYING LGPL-2.1-or-later
}
