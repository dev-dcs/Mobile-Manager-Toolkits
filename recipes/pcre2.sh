# pcre2 - needed by libselinux inside android-tools
deps=""

build() {
	cmake_build -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_BUILD_TESTS=OFF -DPCRE2_SUPPORT_JIT=OFF
	cmake_install
}
