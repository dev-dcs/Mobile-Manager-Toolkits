# libusbmuxd - usbmuxd client library
deps="libplist limd-glue libusb"
provides=""

build() {
	auto_build
	make -C "$BLD" install >/dev/null
}
