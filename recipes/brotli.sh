# brotli lib + cli (OTA system.new.dat.br)
deps=""
provides="brotli"

build() {
	cmake_build -DBROTLI_DISABLE_TESTS=ON
	cmake_install
	put_bin "$BLD/brotli"
	put_license LICENSE
}
