#!/system/bin/sh
# fb doctor - is this phone ready to drive other devices
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

short=0
[ "$1" = --short ] && short=1
[ "$1" = -h ] && { echo "fb doctor [--short]"; exit 0; }

ok()  { printf '  [ok] %s\n' "$*"; }
bad() { printf '  [!!] %s\n' "$*"; fails=$((fails + 1)); }
inf() { [ $short = 1 ] || printf '  [..] %s\n' "$*"; }
fails=0

msg "FlashBench doctor"

[ "$(id -u)" = 0 ] && ok "root" || bad "not root, usb nodes need it"

api=$(getprop ro.build.version.sdk)
if [ "${api:-0}" -ge 35 ]; then ok "Android $(getprop ro.build.version.release) (API $api)"
else bad "API $api, FlashBench targets Android 15-17"; fi

abi=$(getprop ro.product.cpu.abi)
[ "$abi" = arm64-v8a ] && ok "$abi" || bad "abi $abi, binaries are arm64 only"

ps=$(getconf PAGESIZE 2>/dev/null)
inf "kernel $(uname -r)"
. "$FB_LIB/elf.sh"
unmap=""
for f in /system/bin/.adb /system/bin/.fastboot $(awk '$1 == "bin" { print "/system/bin/" $3 }' "$FB_MOD/build.info" 2>/dev/null); do
	[ -f "$f" ] || f=${f%/*}/fb-${f##*/}
	[ -f "$f" ] || continue
	elf_maps "$f" "${ps:-4096}"
	[ $? = 1 ] && unmap="$unmap ${f##*/}"
done
if [ -z "$unmap" ]; then ok "page size ${ps:-?}, every binary maps (4K/16K build)"
else bad "page size $ps, cannot map:$unmap"; fi
inf "SELinux $(getenforce 2>/dev/null)"

if [ -d /sys/bus/usb/devices ] && ls /sys/bus/usb/devices | grep -q '^usb'; then
	ok "USB host controller present"
else
	bad "no USB root hub, OTG off or unsupported (some ROMs have an OTG toggle)"
fi
[ -d /dev/bus/usb ] && ok "usbfs at /dev/bus/usb" || bad "/dev/bus/usb missing, libusb tools will not see devices"

for t in adb fastboot heimdall qdl spd_dump rkdeveloptool magiskboot payload-dumper-go lz4 sqlite3; do
	p=$(command -v "$t" 2>/dev/null || command -v "fb-$t" 2>/dev/null)
	if [ -z "$p" ]; then
		grep -q " \.\{0,1\}$t\$" "$FB_MOD/build.info" 2>/dev/null && bad "$t shipped but not in PATH (module mounted?)"
		continue
	fi
	case $t in
		adb)      v=$("$p" version 2>/dev/null | sed -n 's/^Version //p') ;;
		fastboot) v=$("$p" --version 2>/dev/null | sed -n 's/^fastboot version //p') ;;
		heimdall) v=$("$p" version 2>/dev/null) ;;
		*)        v=present ;;
	esac
	if [ -n "$v" ]; then
		[ $short = 1 ] || ok "$t $v"
	else
		bad "$t does not run ($p)"
	fi
done
[ $short = 1 ] && [ $fails = 0 ] && ok "binaries run"

inf "adb keys in $FB_DATA/home/.android"
inf "config $FB_CONF"

[ $fails = 0 ] && msg "all good" || msg "$fails problem(s)"
