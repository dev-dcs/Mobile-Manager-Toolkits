# rkdeveloptool - Rockchip maskrom/loader mode
deps="libusb"
provides="rkdeveloptool"

build() {
	printf '#define PACKAGE_VERSION "1.32-%s"\n' "${PIN:0:7}" > config.h
	# shellcheck disable=SC2046
	"$CXX" $CXXFLAGS -I. $(pkg-config --cflags libusb-1.0) -o rkdeveloptool ./*.cpp \
		$LDFLAGS $(pkg-config --static --libs libusb-1.0)
	put_bin rkdeveloptool
	put_license license.txt
}
