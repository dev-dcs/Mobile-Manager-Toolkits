# odin4 - Samsung Thor protocol flash tool (open-source CLI)
deps="libusb cryptopp lz4 zlib"
provides="odin4"

build() {
	# CLI only: the Qt6 GUI and the test suite need host packages we don't ship
	cmake_build -DODIN4_BUILD_GUI=OFF -DODIN4_BUILD_TESTS=OFF \
		-DCMAKE_CXX_FLAGS="$CXXFLAGS -I$PREFIX/include" \
		-DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS -L$PREFIX/lib -lcryptopp -lpthread"
	put_bin "$BLD/odin4"
	put_license LICENSE
}
