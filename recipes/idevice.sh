# idevice-tools - Rust iOS tooling (jkcoxson). libimobiledevice owns the classic
# idevice* names, so ship only this crate's distinct binaries.
deps="libusb"
provides="idevice-tools"

build() {
	PKG_CONFIG_ALLOW_CROSS=1 cargo_build
	put_bin "$CARGO_OUT/idevice-tools"
	# iproxy (usbmux TCP relay) and pair_host are unique to this crate
	for b in iproxy pair_host pair_apple_tv; do
		[ -f "$CARGO_OUT/$b" ] && put_bin "$CARGO_OUT/$b"
	done
	put_license LICENSE 2>/dev/null || true
}
