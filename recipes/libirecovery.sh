# libirecovery - Apple iBoot/recovery mode library + irecovery CLI
deps="libusb libplist limd-glue"
provides="irecovery"

build() {
	auto_build --without-udev
	make -C "$BLD" install >/dev/null
	# statically linked, no libtool .libs/ wrapper
	put_bin "$BLD/tools/irecovery" irecovery
	put_license COPYING
}
