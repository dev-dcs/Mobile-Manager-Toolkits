# libtatsu - Apple TATSU/TSS library (needs libcurl for TSS requests)
deps="libplist curl"
provides=""

build() {
	auto_build
	make -C "$BLD" install >/dev/null
}
