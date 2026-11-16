# liblzma for payload-dumper-go, xz cli for images
deps=""
provides="xz"

build() {
	cmake_build -DBUILD_TESTING=OFF -DXZ_NLS=OFF -DXZ_DOC=OFF \
		-DXZ_TOOL_XZDEC=OFF -DXZ_TOOL_LZMADEC=OFF -DXZ_TOOL_LZMAINFO=OFF -DXZ_TOOL_SCRIPTS=OFF
	cmake_install
	put_bin "$BLD/xz"
	put_license COPYING COPYING.0BSD
}
