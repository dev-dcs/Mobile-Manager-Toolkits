# libplist - Apple plist library (needed by all libimobiledevice tools)
deps=""
provides=""

build() {
	auto_build --without-cython
	make -C "$BLD" install >/dev/null
}
