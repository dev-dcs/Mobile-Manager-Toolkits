# busybox - full applet set for the on-device shell (grep, find, vi, awk, tar,
# unzip, xxd and the rest). vendored as the prebuilt static arm64 NDK build, so
# there is nothing to compile; the raw file is already the binary.
deps=""
provides="busybox"

build() {
	# the raw fetch dropped the single file in as busybox-arm64
	put_bin busybox-arm64 busybox
	printf 'busybox, GPLv2\nprebuilt arm64 from the busybox-ndk module (osm0sis)\nhttps://github.com/Magisk-Modules-Repo/busybox-ndk\n' > NOTICE
	put_license NOTICE
}
