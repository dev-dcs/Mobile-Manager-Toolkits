# htop - process viewer
deps="ncurses"
provides="htop"

build() {
	auto_build --enable-unicode --disable-sensors --disable-capabilities \
		--disable-hwloc --disable-delayacct
	put_bin "$BLD/htop"
	put_license COPYING
}
