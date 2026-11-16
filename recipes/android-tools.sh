# adb, fastboot and the AOSP image tools (nmeum/android-tools, vendored AOSP sources)
deps="libusb zlib lz4 zstd brotli pcre2 protobuf"
provides="adb fastboot append2simg img2simg simg2img ext2simg lpadd lpdump lpflash lpmake lpunpack mke2fs.android e2fsdroid make_f2fs sload_f2fs"

build() {
	# libziparchive includes <gtest/gtest_prod.h> (for FRIEND_TEST) but the
	# vendored googletest include dir is not on its path. On CI the system
	# libgtest headers happen to satisfy it; add the vendored path so the build
	# is hermetic and does not depend on host gtest.
	local gtest_inc
	gtest_inc=$(find "$SRC" -path '*/googletest/include/gtest/gtest_prod.h' 2>/dev/null |
		head -n 1 | sed 's|/gtest/gtest_prod.h||')
	cmake_build -DANDROID_TOOLS_PATCH_VENDOR=OFF -DANDROID_TOOLS_USE_BUNDLED_FMT=ON \
		-DProtobuf_PROTOC_EXECUTABLE="$HOSTP/bin/protoc" \
		-DCMAKE_CXX_FLAGS="$CXXFLAGS ${gtest_inc:+-I$gtest_inc} -Wno-deprecated-declarations -Wno-unused-command-line-argument"
	cmake --install "$BLD" --prefix "$BLD/inst" >/dev/null
	local b
	for b in $provides; do
		put_bin "$BLD/inst/bin/$b"
	done
	put_license LICENSE vendor/core/NOTICE
}
