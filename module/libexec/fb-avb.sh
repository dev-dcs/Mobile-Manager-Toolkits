#!/system/bin/sh
# fb avb - Android Verified Boot tool (vendored AOSP avbtool.py) plus a couple
# of shortcuts. @Dev_DcS
#
#   fb avb info <image>              avbtool info_image
#   fb avb verify <image>           avbtool verify_image
#   fb avb disable <vbmeta.img>     set the verification-disable flags in place
#   fb avb <anything...>            passed straight to avbtool
#
# "disable" flips AVB_VBMETA_IMAGE_FLAGS: bit0 HASHTREE_DISABLED, bit1
# VERIFICATION_DISABLED. It edits a copy and keeps the original as .orig.

. "${0%/*}/../lib/common.sh"
. "$FB_LIB/py.sh"

AVB=$FB_MOD/share/py/avbtool.py
[ -f "$AVB" ] || die "avbtool.py missing from this build"

case $1 in
	''|-h|--help)
		echo "fb avb info|verify|disable <image> | <avbtool args...>"
		echo "avbtool help follows:"; pyrun "$AVB" --help 2>&1 | head -40; exit 0 ;;
	info) shift; pyrun "$AVB" info_image --image "$1" ;;
	verify) shift; pyrun "$AVB" verify_image --image "$1" ;;
	disable)
		img=$2
		[ -f "$img" ] || die "fb avb disable <vbmeta.img>"
		# the magic header starts with "AVB0"; flags live at byte offset 123
		[ "$(dd if="$img" bs=1 count=4 2>/dev/null)" = "AVB0" ] || die "$img is not a vbmeta image"
		cp "$img" "$img.orig"
		# read current flags byte, OR in 0x03, write it back
		cur=$(od -An -tu1 -j 123 -N 1 "$img" | tr -d ' ')
		new=$(( cur | 3 ))
		printf "$(printf '\\%03o' "$new")" | dd of="$img" bs=1 seek=123 count=1 conv=notrunc 2>/dev/null
		msg "flags byte 123: $cur -> $new (hashtree + verification disabled)"
		msg "original kept as $img.orig; re-sign vbmeta if your bootloader checks its signature"
		;;
	*) pyrun "$AVB" "$@" ;;
esac
