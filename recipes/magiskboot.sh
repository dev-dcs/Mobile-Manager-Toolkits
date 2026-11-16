# magiskboot - boot/vendor_boot unpack + repack, taken from the Magisk release apk
# (it is already a static aarch64 executable shipped as a .so)
deps=""
provides="magiskboot"

build() {
	unzip -p ./*.apk lib/arm64-v8a/libmagiskboot.so > magiskboot
	[ -s magiskboot ] || die "magiskboot: not found in apk"
	put_bin magiskboot
	printf 'magiskboot from Magisk %s, GPL-3.0\nhttps://github.com/topjohnwu/Magisk\n' "$REF" > NOTICE
	put_license NOTICE
}
