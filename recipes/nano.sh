# nano - the editor, for when vi is a step too far on a phone screen. vendored
# as the prebuilt static arm64 NDK build plus its terminfo set, from the nano-ndk
# module. The thin launcher that points TERMINFO at /system/etc/terminfo is
# committed in module/system/bin/nano; here we just stage the real binary and
# the terminfo database.
deps=""
provides="nano.bin"

build() {
	put_bin bin/nano.bin-arm64 nano.bin
	put_system etc/terminfo etc/terminfo
	for l in COPYING COPYING.DOC LICENSE.md; do
		[ -f "$l" ] && put_license "$l"
	done
	printf 'nano, GPLv3; terminfo from ncurses (MIT-style)\nprebuilt arm64 from the nano-ndk module (osm0sis)\nhttps://github.com/Magisk-Modules-Repo/nano-ndk\n' > NOTICE
	put_license NOTICE
}
