# libimobiledevice-glue - helper library used by libusbmuxd / libimobiledevice
deps="libplist"
provides=""

build() {
	auto_build
	make -C "$BLD" install >/dev/null
}
