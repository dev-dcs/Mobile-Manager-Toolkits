# ncurses - static lib for htop and tmux
# nano ships the terminfo database this reads, so it comes along as a dep
deps="nano"

build() {
	auto_build --without-shared --without-cxx --without-cxx-binding --without-ada \
		--without-progs --without-tests --without-manpages --disable-db-install \
		--enable-widec --enable-pc-files --with-pkg-config-libdir="$PREFIX/lib/pkgconfig" \
		--with-default-terminfo-dir=/system/etc/terminfo \
		--with-terminfo-dirs=/system/etc/terminfo:/data/data/com.termux/files/usr/share/terminfo:/etc/terminfo
	make -C "$BLD" install >/dev/null
}
