# heimdall - Samsung download mode (Odin protocol), Grimler's maintained fork
deps="libusb"
provides="heimdall"

build() {
	cmake_build -DDISABLE_FRONTEND=ON
	put_bin "$BLD/bin/heimdall"
	put_license LICENSE
}
