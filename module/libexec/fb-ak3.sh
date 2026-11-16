#!/system/bin/sh
# fb ak3 - turn an AnyKernel3 flashable zip into a boot.img you can
# fastboot flash or fastboot boot. The kernel from the zip goes into a
# base boot image of the right device, then magiskboot repacks it.
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

usage() {
	cat <<EOF
fb ak3 <AnyKernel3.zip> <base> [options]

base boot image, one of:
  --boot <boot.img>          an image you already have (stock or current)
  --from-device [-s serial]  read boot of a connected rooted device
                             (or fastboot fetch from fastbootd)
  --from-ota <ota.zip|payload.bin>
  --from-self                this phone's own active boot partition

options:
  -o <file>      output (default $FB_OUT/ak3/<zip name>-boot.img)
  --test-boot    fastboot boot the result on the connected device, nothing flashed
  --force        ignore the zip's device check
EOF
}

zip='' base_mode='' base_arg='' out='' testboot=0 force=0
while [ $# -gt 0 ]; do
	take_serial "$@" && { [ "$1" = -s ] && shift; shift; continue; }
	case $1 in
		--boot) base_mode=file base_arg=$2; shift ;;
		--from-device) base_mode=device ;;
		--from-ota) base_mode=ota base_arg=$2; shift ;;
		--from-self) base_mode=self ;;
		-o) out=$2; shift ;;
		--test-boot) testboot=1 ;;
		--force) force=1 ;;
		-h|--help) usage; exit 0 ;;
		-*) die "unknown option $1" ;;
		*) zip=$1 ;;
	esac
	shift
done

[ -f "$zip" ] || { usage; exit 1; }
[ -n "$base_mode" ] || die "say where the base boot image comes from (--boot, --from-device, --from-ota, --from-self)"
command -v magiskboot >/dev/null 2>&1 || die "magiskboot is not in this build"

W=${TMPDIR:-/data/local/tmp}/fb-ak3.$$
trap 'rm -rf "$W"' EXIT INT TERM
mkdir -p "$W/zip" "$W/img" "$W/k"

name=$(basename "$zip" .zip)
out=${out:-$FB_OUT/ak3/$name-boot.img}
mkdir -p "$(dirname "$out")"

# ---- read the zip ------------------------------------------------------

unzip -q -o "$zip" -d "$W/zip" 2>/dev/null || die "cannot unzip $zip"
ak=$W/zip/anykernel.sh
[ -f "$ak" ] || die "no anykernel.sh, not an AnyKernel3 zip"

akprop() { sed -n "s/^[[:space:]]*$1=\(.*\)$/\1/p" "$ak" | head -n 1 | sed "s/;*[[:space:]]*$//; s/^[\"']//; s/[\"']$//"; }

kstring=$(akprop kernel.string)
block=$(akprop BLOCK)
[ -n "$block" ] || block=$(akprop block)
msg "zip      ${kstring:-$name}"

case $block in *vendor_boot*|*init_boot*)
	die "this zip targets $block, not boot; there is no boot.img to make from it" ;;
esac

kfile=""
for k in Image.lz4-dtb Image.gz-dtb Image-dtb Image.lz4 Image.gz Image zImage-dtb zImage; do
	[ -f "$W/zip/$k" ] && { kfile=$W/zip/$k; break; }
done
[ -n "$kfile" ] || die "no kernel image (Image, Image.gz, Image.lz4 ...) in the zip"
msg "kernel   ${kfile##*/}"

notes=""
note() { notes="$notes
  - $*"; }
grep -qE '^[[:space:]]*(patch_cmdline|patch_prop|patch_fstab|replace_string|replace_section|insert_line|replace_line|remove_line|append_file|prepend_file|insert_file|replace_file)' "$ak" &&
	note "anykernel.sh patches the ramdisk/cmdline, those edits are not applied here"
[ -d "$W/zip/ramdisk" ] && [ -n "$(ls -A "$W/zip/ramdisk" 2>/dev/null)" ] && note "ramdisk/ overlay files in the zip are not added"
[ -d "$W/zip/modules" ] && [ -n "$(find "$W/zip/modules" -type f ! -name placeholder 2>/dev/null)" ] &&
	note "the zip carries kernel modules (vendor_dlkm); a boot.img cannot hold them"
[ -f "$W/zip/dtbo.img" ] && note "dtbo.img copied next to the output, flash it too: fastboot flash dtbo <file>"

# ---- base boot image ---------------------------------------------------

dev_codename=""
base=$W/base.img
case $base_mode in
file)
	[ -f "$base_arg" ] || die "no such file: $base_arg"
	cp "$base_arg" "$base"
	;;
self)
	need_root
	slot=$(getprop ro.boot.slot_suffix)
	dd if="/dev/block/by-name/boot$slot" of="$base" bs=1048576 2>/dev/null || die "cannot read boot$slot"
	dev_codename=$(getprop ro.product.device)
	;;
device)
	if [ -n "$(adb_devices)" ]; then
		pick_device
		target_has_su || die "reading boot over adb needs su on the target (or use fastbootd)"
		slot=$(prop ro.boot.slot_suffix)
		bn=$(target_byname)
		A exec-out "su -c 'cat $bn/boot$slot'" < /dev/null > "$base"
		dev_codename=$(prop ro.product.device)
	elif fastboot devices 2>/dev/null | grep -q .; then
		fastboot fetch boot "$base" || die "fastboot fetch failed (only works in fastbootd)"
		dev_codename=$(fastboot getvar product 2>&1 | sed -n 's/^product: *//p')
	else
		die "no device over adb or fastboot"
	fi
	;;
ota)
	[ -f "$base_arg" ] || die "no such file: $base_arg"
	pd=$(command -v payload-dumper-go || command -v fb-payload-dumper-go) || die "payload-dumper-go is not in this build"
	"$pd" -o "$W/ota" -p boot "$base_arg" >/dev/null 2>&1
	[ -f "$W/ota/boot.img" ] || die "no boot partition in that OTA"
	mv "$W/ota/boot.img" "$base"
	;;
esac

[ "$(head -c 8 "$base" 2>/dev/null)" = "ANDROID!" ] || die "base is not an Android boot image"

if [ -n "$dev_codename" ] && [ "$(akprop do.devicecheck)" = 1 ]; then
	names=$(grep -E '^[[:space:]]*device\.name[0-9]+=' "$ak" | sed 's/.*=//; s/["'\'']//g' | grep . | tr '\n' ' ')
	case " $names " in
		*" $dev_codename "*) msg "device   $dev_codename (listed in the zip)" ;;
		*)
			[ $force = 1 ] || die "zip is for: $names; base comes from $dev_codename (--force to ignore)"
			warn "zip is for $names, base is $dev_codename, going on (--force)"
			;;
	esac
fi

# ---- swap the kernel ---------------------------------------------------

cd "$W/img" || exit 1
magiskboot unpack -h "$base" > "$W/unpack.log" 2>&1 || { cat "$W/unpack.log"; die "magiskboot could not unpack the base"; }
[ -f kernel ] || die "the base image has no kernel (init_boot or vendor_boot given by mistake?)"
hv=$(sed -n 's/.*HEADER_VER *\[\([0-9]*\)\].*/\1/p' "$W/unpack.log")
kf=$(sed -n 's/.*KERNEL_FMT *\[\([^]]*\)\].*/\1/p' "$W/unpack.log")
msg "base     header v${hv:-?}, kernel ${kf:-?}"

kver() { grep -a -o -m 1 'Linux version [^ ]* ([^)]*)' "$1" 2>/dev/null | head -n 1; }
old_ver=$(kver kernel)

raw=$W/k/kernel
case ${kfile##*/} in
*-dtb)
	(cd "$W/k" && magiskboot split "$kfile" >/dev/null 2>&1) || die "could not split ${kfile##*/}"
	[ -f "$W/k/kernel" ] || die "split gave no kernel"
	if [ -f kernel_dtb ]; then
		cp "$W/k/kernel_dtb" kernel_dtb
	else
		note "the zip appends a dtb but this base does not use one, it was dropped"
	fi
	;;
*)
	cp "$kfile" "$W/k/kernel.in"
	magic=$(head -c 4 "$kfile" | od -An -t x1 | tr -d ' \n')
	case $magic in
		1f8b*|02214c18|04224d18)
			magiskboot decompress "$W/k/kernel.in" "$raw" >/dev/null 2>&1 || die "could not decompress the kernel" ;;
		*) mv "$W/k/kernel.in" "$raw" ;;
	esac
	;;
esac
cp "$raw" kernel

# a dtb shipped loose in the zip replaces the base one (header v2/v3 style)
if [ -f dtb ]; then
	for d in "$W/zip/dtb" "$W/zip"/*.dtb; do
		[ -f "$d" ] && { cp "$d" dtb; msg "dtb      replaced from ${d##*/}"; break; }
	done
fi

new_ver=$(kver kernel)
msg "old      ${old_ver:-?}"
msg "new      ${new_ver:-not found in the image}"

magiskboot repack "$base" "$W/new.img" > "$W/repack.log" 2>&1 || { cat "$W/repack.log"; die "repack failed"; }
cd - >/dev/null || true
cp "$W/new.img" "$out"
[ -f "$W/zip/dtbo.img" ] && cp "$W/zip/dtbo.img" "${out%.img}-dtbo.img"

msg ""
msg "$out"
msg "sha256 $(sha256sum "$out" | cut -d' ' -f1)"
[ -n "$notes" ] && msg "notes:$notes"
msg ""
msg "try it first:  fastboot boot $out   (if the bootloader allows it)"
msg "flash:         fastboot flash boot $out"

if [ $testboot = 1 ]; then
	fastboot devices 2>/dev/null | grep -q . || die "--test-boot needs the target in fastboot"
	fastboot boot "$out"
fi
