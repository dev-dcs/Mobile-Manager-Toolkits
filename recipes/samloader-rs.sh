# samloader-rs - Samsung firmware download + flash (Rust, topjohnwu)
# the workspace has a wasm `web` cdylib member that can't target musl, so build
# only the samloader CLI package
deps="libusb"
provides="samloader"

build() {
	PKG_CONFIG_ALLOW_CROSS=1 cargo_build -p samloader
	put_bin "$CARGO_OUT/samloader" samloader
	put_license LICENSE-APACHE LICENSE-MIT 2>/dev/null || true
}
