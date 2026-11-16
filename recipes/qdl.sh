# qdl - Qualcomm EDL (Sahara + Firehose)
deps="libusb libxml2"
provides="qdl"

build() {
	# qdl #defines __unused, same name as a musl struct stat member. rename it
	# in qdl's own tree before it detonates.
	grep -rl '__unused' include src 2>/dev/null |
		xargs -r sed -i 's/\b__unused\b/__qdl_unused/g'
	meson_build -Dzip-container=disabled -Dtests=disabled \
		-Dnbdkit=disabled -Dudev=disabled
	put_bin "$BLD/qdl"
	put_license LICENSE
}
