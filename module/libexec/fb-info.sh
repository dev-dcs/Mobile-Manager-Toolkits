#!/system/bin/sh
# fb info - one screen about whatever is connected (adb, fastboot, odin)
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

while [ $# -gt 0 ]; do
	take_serial "$@" && { [ "$1" = -s ] && shift; shift; continue; }
	case $1 in
		-h|--help) echo "fb info [-s serial]"; exit 0 ;;
		*) die "unknown option $1" ;;
	esac
done

row() { printf '  %-18s %s\n' "$1" "$2"; }

adb_info() {
	pick_device
	msg "adb: $SERIAL"
	getp=$(ash getprop | tr -d '\r')
	p() { echo "$getp" | sed -n "s/^\[$1\]: \[\(.*\)\]$/\1/p"; }
	row model "$(p ro.product.manufacturer) $(p ro.product.model) ($(p ro.product.device))"
	row android "$(p ro.build.version.release) / API $(p ro.build.version.sdk) / $(p ro.build.type)"
	row patch "$(p ro.build.version.security_patch)"
	row build "$(p ro.build.display.id)"
	row fingerprint "$(p ro.build.fingerprint)"
	row soc "$(p ro.soc.manufacturer) $(p ro.soc.model) $(p ro.board.platform)"
	row slot "$(p ro.boot.slot_suffix)"
	row "verified boot" "$(p ro.boot.verifiedbootstate)"
	row bootloader "$(p ro.boot.vbmeta.device_state) $(p ro.bootloader)"
	row encryption "$(p ro.crypto.state) $(p ro.crypto.type)"
	row selinux "$(ash getenforce | tr -d '\r')"
	row "battery" "$(ash dumpsys battery | tr -d '\r' | sed -n 's/^  level: //p')%"
	row uptime "$(ash uptime | tr -d '\r' | sed 's/^ *//')"
}

fb_info() {
	msg "fastboot: $1"
	vars=$(fastboot -s "$1" getvar all 2>&1 | sed -n 's/^(bootloader) //p')
	for k in product serialno version-bootloader version-baseband unlocked secure current-slot is-userspace max-download-size hw-revision; do
		v=$(echo "$vars" | sed -n "s/^$k: *//p" | head -n 1)
		[ -n "$v" ] && row "$k" "$v"
	done
	n=$(echo "$vars" | grep -c '^partition-size:')
	row partitions "$n"
}

found=0
if [ -n "$(adb_devices)" ]; then adb_info; found=1; fi

for s in $(fastboot devices 2>/dev/null | awk '{print $1}'); do
	[ -n "$SERIAL" ] && [ "$s" != "$SERIAL" ] && continue
	fb_info "$s"; found=1
done

if command -v heimdall >/dev/null 2>&1 && heimdall detect >/dev/null 2>&1; then
	msg "samsung download mode: detected"
	row next "fb samsung pit   (reads the partition table)"
	found=1
fi

[ $found = 1 ] || { msg "nothing over adb, fastboot or odin. other modes:"; sh "${0%/*}/fb-usb.sh"; }
