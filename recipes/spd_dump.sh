# spd_dump - Unisoc/Spreadtrum download mode
deps="libusb"
provides="spd_dump"

build() {
	# shellcheck disable=SC2046
	"$CC" $CFLAGS -std=c99 -DUSE_LIBUSB=1 $(pkg-config --cflags libusb-1.0) \
		-o spd_dump spd_dump.c $LDFLAGS $(pkg-config --static --libs libusb-1.0)
	put_bin spd_dump
	put_license LICENSE README.md
}
