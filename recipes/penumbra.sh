# penumbra/antumbra - MediaTek V5/V6 flash, readback, unlock (Rust)
deps="libusb"
provides="antumbra"

build() {
	PKG_CONFIG_ALLOW_CROSS=1 cargo_build --bin antumbra
	put_bin "$CARGO_OUT/antumbra"
	put_license LICENSE
}
