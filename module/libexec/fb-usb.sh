#!/system/bin/sh
# fb usb - lists USB devices on this phone's host port and guesses their mode
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

SYS=${FB_SYSFS:-/sys}/bus/usb/devices

usage() {
	cat <<EOF
fb usb [-w]

  -w   keep watching, print plug/unplug and mode changes
EOF
}

rd() { cat "$1" 2>/dev/null | tr -d '\r\n'; }

# mode + tool for one device directory
classify() {
	d=$1 vid=$(rd "$d/idVendor") pid=$(rd "$d/idProduct")
	ifs=""
	for i in "$d"/"${d##*/}":*; do
		[ -f "$i/bInterfaceClass" ] || continue
		ifs="$ifs $(rd "$i/bInterfaceClass")/$(rd "$i/bInterfaceSubClass")/$(rd "$i/bInterfaceProtocol")"
	done

	case "$vid:$pid" in
		04e8:685d)      echo "samsung-download heimdall"; return ;;
		05c6:9008)      echo "qualcomm-edl qdl"; return ;;
		05c6:900e)      echo "qualcomm-ramdump qdl"; return ;;
		05c6:901d|05c6:9025|05c6:9091|05c6:90b6|05c6:90db|05c6:90e5|05c6:9039)
		                echo "qualcomm-diag qcdiag"; return ;;
		0e8d:0003)      echo "mtk-brom mtkclient"; return ;;
		0e8d:2000)      echo "mtk-preloader mtkclient"; return ;;
		0e8d:2001)      echo "mtk-da mtkclient"; return ;;
		1782:4d00)      echo "unisoc-download spd_dump"; return ;;
		2207:*)         echo "rockchip-usb rkdeveloptool"; return ;;
		1f3a:efe8)      echo "allwinner-fel sunxi-fel"; return ;;
		# Apple
		05ac:1227)      echo "apple-dfu gaster"; return ;;
		05ac:1281)      echo "apple-recovery irecovery"; return ;;
		05ac:12a8|05ac:12ab) echo "apple-normal fb-ios"; return ;;
		# Samsung Exynos download
		04e8:1234)      echo "exynos-download exynos-usbdl"; return ;;
	esac

	case " $ifs " in
		*" ff/42/03 "*) echo "fastboot fastboot"; return ;;
		*" ff/42/01 "*) echo "adb adb"; return ;;
	esac
	case "$vid:$pid" in
		18d1:4ee0|18d1:d00d) echo "fastboot fastboot"; return ;;
	esac
	case " $ifs " in
		*" ff/ff/30 "*) echo "qualcomm-diag qcdiag" ;;
		*" 02/02/"*)    echo "serial-modem atcmd" ;;
		*" 06/01/01 "*) echo "mtp/ptp -" ;;
		*" 08/"*)       echo "mass-storage -" ;;
		*" 09/"*)       echo "hub -" ;;
		*)              echo "other -" ;;
	esac
}

hint() {
	case $1 in
		mtp/ptp)          echo "no adb interface: turn on USB debugging on the target" ;;
		mtk-*)            echo "MediaTek: mtkclient (python, e.g. Termux) is not bundled" ;;
		allwinner-fel)    echo "Allwinner FEL: sunxi-fel is not bundled" ;;
		qualcomm-ramdump) echo "device crashed into Sahara memory dump mode" ;;
		qualcomm-diag)    echo "fb modem nv/efs/bands talk to this port" ;;
		serial-modem)     echo "AT port: fb modem at -l $2 <command>" ;;
		apple-dfu)        echo "DFU mode: fb ios gaster (checkm8 A5-A11) or irecovery" ;;
		apple-recovery)   echo "recovery mode: fb ios recovery info" ;;
		apple-normal)     echo "normal mode: fb ios info, fb ios pair" ;;
		mtk-brom|mtk-preloader|mtk-da)  echo "fb mtk (penumbra/mtkclient)" ;;
		exynos-download)  echo "Exynos download: fb samsung or exynos-usbdl" ;;
	esac
}

scan() {
	for d in "$SYS"/*; do
		case ${d##*/} in *:*|usb*) continue ;; esac
		[ -f "$d/idVendor" ] || continue
		set -- $(classify "$d")
		printf '%s|%s:%s|%s|%s|%s|%s\n' "$(rd "$d/busnum"):$(rd "$d/devnum")" \
			"$(rd "$d/idVendor")" "$(rd "$d/idProduct")" "$1" "$2" \
			"$(rd "$d/manufacturer") $(rd "$d/product")" "$(rd "$d/serial")"
	done
}

table() {
	if [ -z "$1" ]; then
		msg "nothing plugged in (check the OTG cable / OTG toggle in settings)"
		return
	fi
	printf '%-7s %-9s %-17s %-13s %s\n' BUS:DEV ID MODE TOOL DEVICE
	echo "$1" | while IFS='|' read -r bd id mode tool name serial; do
		printf '%-7s %-9s %-17s %-13s %s%s\n' "$bd" "$id" "$mode" "$tool" "$name" "${serial:+ [$serial]}"
		h=$(hint "$mode" "$id")
		[ -n "$h" ] && printf '%39s%s\n' '' "$h"
	done
}

case $1 in
	-h|--help) usage; exit 0 ;;
	-w)
		[ -d "$SYS" ] || die "no $SYS, this kernel has no USB host support"
		prev=""
		while :; do
			cur=$(scan)
			if [ "$cur" != "$prev" ]; then
				printf '\n[%s]\n' "$(date +%T)"
				table "$cur"
				prev=$cur
			fi
			sleep 1
		done
		;;
	'')
		[ -d "$SYS" ] || die "no $SYS, this kernel has no USB host support"
		table "$(scan)"
		;;
	*) usage; exit 1 ;;
esac
