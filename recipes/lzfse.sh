# lzfse - Apple LZFSE compression (img4tool needs it for IMG4 payloads)
deps=""
provides=""

build() {
	cmake_build -DLZFSE_DISABLE_TESTS=ON -DBUILD_SHARED_LIBS=OFF
	cmake_install
}
