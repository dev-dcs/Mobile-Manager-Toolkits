# gaster - checkm8 BootROM exploit for A5-A11 (native C, libusb + openssl)
deps="libusb openssl"
provides="gaster"

build() {
	# the Makefile's libusb target hardcodes flags without our -I/-L, so compile
	# directly: generate the payload headers, then build with HAVE_LIBUSB
	for p in payload_A9 payload_notA9 payload_notA9_armv7 \
		payload_handle_checkm8_request payload_handle_checkm8_request_armv7; do
		[ -f "$p.bin" ] && xxd -iC "$p.bin" "$p.h"
	done
	# shellcheck disable=SC2046
	"$CC" $CFLAGS -DHAVE_LIBUSB $(pkg-config --cflags libusb-1.0) \
		gaster.c lzfse.c -o gaster \
		$LDFLAGS $(pkg-config --static --libs libusb-1.0) -lcrypto
	put_bin gaster
	put_license LICENSE
}
