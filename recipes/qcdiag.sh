# qcdiag - Qualcomm DIAG client: NV, EFS, SPC (tools/qcdiag.c)
deps="libusb"
provides="qcdiag"

build() {
	# shellcheck disable=SC2046
	"$CC" $CFLAGS -std=c99 -Wall -DHAVE_LIBUSB $(pkg-config --cflags libusb-1.0) \
		-o qcdiag qcdiag.c $LDFLAGS $(pkg-config --static --libs libusb-1.0)
	put_bin qcdiag
}
