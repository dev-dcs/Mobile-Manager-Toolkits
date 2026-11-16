# mtools - read/write the FAT modem image (NON-HLOS) without mounting it
deps=""
provides="mtools"

build() {
	auto_build --without-x --disable-floppyd
	put_bin "$BLD/mtools"
	put_license COPYING
}
