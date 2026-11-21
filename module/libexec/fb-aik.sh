#!/system/bin/sh
# fb aik - Android Image Kitchen style boot image editing, over magiskboot.
# Unpack a boot/recovery/vendor_boot image into parts, edit, repack.
# @Dev_DcS

. "${0%/*}/../lib/common.sh"
command -v magiskboot >/dev/null 2>&1 || die "magiskboot not in this build"

usage() {
	cat <<EOF
fb aik <command>

  unpack <image> [dir]     split into kernel / ramdisk / dtb / header (dir
                           defaults to <image>.aik)
  repack <dir> [out.img]   rebuild from a dir made by unpack (needs the
                           original image kept in that dir as base.img)
  info <image>             header version, kernel format, sizes
  cleanup <dir>            remove an unpack dir

Edit ramdisk files or cmdline in the dir, then repack. magiskboot keeps the
ramdisk as ramdisk.cpio; unpack it further with:  magiskboot cpio ramdisk.cpio extract
EOF
}

cmd=$1
[ -n "$cmd" ] && shift
case $cmd in
unpack)
	img=$1
	[ -f "$img" ] || die "fb aik unpack <image> [dir]"
	# absolutise before we cd
	case $img in /*) ;; *) img=$PWD/$img ;; esac
	dir=${2:-$img.aik}
	mkdir -p "$dir" || die "cannot make $dir"
	cp "$img" "$dir/base.img"
	( cd "$dir" && magiskboot unpack -h base.img ) > "$dir/unpack.log" 2>&1 ||
		{ cat "$dir/unpack.log" >&2; die "unpack failed"; }
	msg "unpacked into $dir:"
	( cd "$dir" && for f in kernel ramdisk.cpio dtb kernel_dtb recovery_dtbo header extra; do
		[ -f "$f" ] && printf '  %-14s %8d B\n' "$f" "$(wc -c < "$f")"
	done )
	hv=$(sed -n 's/.*HEADER_VER *\[\([0-9]*\)\].*/\1/p' "$dir/unpack.log")
	kf=$(sed -n 's/.*KERNEL_FMT *\[\([^]]*\)\].*/\1/p' "$dir/unpack.log")
	msg "header v${hv:-?}, kernel ${kf:-?}"
	msg "edit files in $dir, then: fb aik repack $dir"
	;;
repack)
	dir=$1
	[ -d "$dir" ] && [ -f "$dir/base.img" ] || die "not an unpack dir (no base.img): $dir"
	out=${2:-$dir/new-boot.img}
	case $out in /*) ;; *) out=$PWD/$out ;; esac
	( cd "$dir" && magiskboot repack base.img "$out" ) >/dev/null 2>&1 || die "repack failed"
	msg "$out"
	msg "sha256 $(sha256sum "$out" | cut -d' ' -f1)"
	;;
info)
	[ -f "$1" ] || die "fb aik info <image>"
	t=${TMPDIR:-/data/local/tmp}/fb-aik.$$
	mkdir -p "$t"
	( cd "$t" && magiskboot unpack -n "$(realpath "$1" 2>/dev/null || echo "$OLDPWD/$1")" ) 2>&1 |
		grep -E 'HEADER_VER|KERNEL_FMT|RAMDISK_FMT|KERNEL_SZ|cmdline|OS_VERSION|PAGESIZE' | sed 's/^/  /'
	rm -rf "$t"
	;;
cleanup)
	[ -d "$1" ] && [ -f "$1/base.img" ] || die "not an unpack dir: $1"
	rm -rf "$1" && msg "removed $1"
	;;
''|-h|--help) usage ;;
*) usage; exit 1 ;;
esac
