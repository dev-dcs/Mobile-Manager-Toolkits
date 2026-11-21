# spd_dump_tk - TomKing062's spreadtrum_flash, the command line core sfd_tool is
# built on. sfd_tool itself has GTK wired into its core and has no CLI-only build.
deps="libusb libxml2"
provides="spd_dump_tk"

build() {
	printf '#define GIT_VER "%s"\n#define GIT_SHA1 "%s"\n' "$REF" "$PIN" > GITVER.h
	# shellcheck disable=SC2046
	"$CC" $CFLAGS -std=c99 -DUSE_LIBUSB=1 $(pkg-config --cflags libusb-1.0 libxml-2.0) \
		-o spd_dump_tk spd_dump.c common.c \
		$LDFLAGS $(pkg-config --static --libs libusb-1.0 libxml-2.0) -lm -lpthread
	put_bin spd_dump_tk
	put_license README.md
}
