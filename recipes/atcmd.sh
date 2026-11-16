# atcmd - AT console over tty or CDC-ACM through libusb (tools/atcmd.c)
deps="libusb"
provides="atcmd"

build() {
	# shellcheck disable=SC2046
	"$CC" $CFLAGS -std=c99 -Wall -DHAVE_LIBUSB $(pkg-config --cflags libusb-1.0) \
		-o atcmd atcmd.c $LDFLAGS $(pkg-config --static --libs libusb-1.0)
	put_bin atcmd
}
