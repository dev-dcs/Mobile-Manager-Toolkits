# libusb without udev, Android has none. Enumeration goes through usbfs
deps=""

build() {
	auto_build --disable-udev --disable-examples-build --disable-tests-build
	make -C "$BLD" install >/dev/null
}
