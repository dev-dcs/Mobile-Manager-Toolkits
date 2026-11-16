# futurerestore - iOS restore with custom APTickets / SHSH blobs
deps="libplist libusbmuxd libirecovery libimobiledevice libtatsu zlib"
provides="futurerestore"

build() {
	cmake_build -DCMAKE_CXX_FLAGS="$CXXFLAGS -Wno-deprecated-declarations"
	put_bin "$BLD/src/futurerestore"
	put_license LICENSE
}
