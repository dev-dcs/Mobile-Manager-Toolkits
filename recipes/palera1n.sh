# palera1n-c - native checkm8 jailbreak (A8-A11), builds on gaster
deps="libusb libirecovery libimobiledevice"
provides="palera1n"

build() {
	make -j"$JOBS" \
		CC="$CC" CFLAGS="$CFLAGS $(pkg-config --cflags libusb-1.0 libimobiledevice-1.0 libirecovery-1.0)" \
		LDFLAGS="$LDFLAGS $(pkg-config --static --libs libusb-1.0 libimobiledevice-1.0 libirecovery-1.0)" ||
	cmake_build
	[ -f palera1n ] && put_bin palera1n || put_bin "$BLD/palera1n"
	put_license LICENSE
}
