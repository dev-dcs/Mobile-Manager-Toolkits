# exynos-usbdl - Exynos BootROM USB download exploit
deps="libusb"
provides="exynos-usbdl"

build() {
	# shellcheck disable=SC2046
	"$CC" $CFLAGS $(pkg-config --cflags libusb-1.0) \
		-o exynos-usbdl exynos-usbdl.c \
		$LDFLAGS $(pkg-config --static --libs libusb-1.0)
	put_bin exynos-usbdl
	put_license LICENSE
}
