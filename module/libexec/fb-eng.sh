#!/system/bin/sh
# fb eng - engineering lookup: bootloader unlock status, eng firmware, eng root
# backed by the wall-of-shame DB and SoC-BootROMs data bundle
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

UNLOCK_DB="$FB_MOD/share/unlock-db"
BOOTROM_DIR="$FB_MOD/share/bootroms"

usage() {
	cat <<EOF
fb eng <command> [-s serial]

  unlock [-s serial]     lookup the connected device's bootloader unlock status
                         (brand, SoC, known methods, tier from wall-of-shame)
  brands                 list all brands and their unlock tier
  brand <name>           detail for one brand
  bootroms               list bundled BootROM dumps
  bootrom <soc>          info about a specific SoC dump
  engroot [-s serial]    check if eng root is possible on the connected device
                         and what methods exist
EOF
}

# --- unlock lookup --------------------------------------------------------

tier_label() {
	case $1 in
		avoid*) echo "AVOID - unlocking effectively impossible" ;;
		terrible*) echo "TERRIBLE - depends on region/model/SoC, may need sacrifice" ;;
		caution*) echo "CAUTION - needs internet or waiting period" ;;
		safe*) echo "SAFE FOR NOW - few restrictions" ;;
		*) echo "$1" ;;
	esac
}

find_brand() {
	mfg=$(echo "$1" | tr '[:upper:]' '[:lower:]')
	for d in "$UNLOCK_DB/brands/"*/; do
		name=${d%/}; name=${name##*/}
		case $(echo "$name" | tr '[:upper:]' '[:lower:]') in
			"$mfg"*|*"$mfg"*) echo "$d"; return 0 ;;
		esac
	done
	return 1
}

unlock_lookup() {
	pick_device
	mfg=$(prop ro.product.manufacturer | tr -d '\r')
	model=$(prop ro.product.model | tr -d '\r')
	device=$(prop ro.product.device | tr -d '\r')
	soc_mfg=$(prop ro.soc.manufacturer | tr -d '\r')
	soc_model=$(prop ro.soc.model | tr -d '\r')
	platform=$(prop ro.board.platform | tr -d '\r')
	fp=$(prop ro.build.fingerprint | tr -d '\r')
	bl_state=$(prop ro.boot.vbmeta.device_state | tr -d '\r')
	oem_unlock=$(ash settings get global oem_unlock_enabled | tr -d '\r')

	msg "device:     $mfg $model ($device)"
	msg "SoC:        $soc_mfg $soc_model ($platform)"
	msg "bootloader: ${bl_state:-unknown}"
	msg "OEM unlock: $( [ "$oem_unlock" = 1 ] && echo "enabled in developer options" || echo "not enabled" )"
	echo

	[ -d "$UNLOCK_DB/brands" ] || { warn "unlock DB not bundled in this build"; return 1; }

	brand_dir=$(find_brand "$mfg")
	if [ -z "$brand_dir" ]; then
		msg "brand '$mfg' not in the wall-of-shame database"
		msg "check: https://github.com/zenfyrdev/bootloader-unlock-wall-of-shame"
		return 1
	fi

	readme="$brand_dir/README.md"
	[ -f "$readme" ] || { msg "no data for $mfg"; return 1; }

	# extract tier from the main index
	tier=$(grep -i "$mfg" "$UNLOCK_DB/README.md" 2>/dev/null | head -n 1)
	[ -n "$tier" ] && msg "tier:       $(tier_label "$tier")"
	echo

	# look for the device/SoC specifically
	found=0
	for term in "$device" "$model" "$platform" "$soc_model"; do
		[ -z "$term" ] && continue
		match=$(grep -i "$term" "$readme" | head -n 5)
		if [ -n "$match" ]; then
			msg "mentions of '$term':"
			echo "$match" | sed 's/^/  /'
			found=1
			echo
		fi
	done
	[ $found = 0 ] && msg "no specific mention of $device / $model / $platform in $mfg's page"
	msg "full page: $readme"
}

# --- brands ---------------------------------------------------------------

list_brands() {
	[ -d "$UNLOCK_DB/brands" ] || { warn "unlock DB not bundled"; return 1; }
	for d in "$UNLOCK_DB/brands/"*/; do
		name=${d%/}; name=${name##*/}
		printf '  %s\n' "$name"
	done
}

show_brand() {
	brand_dir=$(find_brand "$1")
	[ -n "$brand_dir" ] || die "brand '$1' not found"
	cat "$brand_dir/README.md" | head -n 80
	msg "..."
	msg "full: $brand_dir/README.md"
}

# --- bootroms -------------------------------------------------------------

list_bootroms() {
	[ -d "$BOOTROM_DIR" ] || { warn "BootROM dumps not bundled"; return 1; }
	for d in "$BOOTROM_DIR"/*/; do
		[ -d "$d" ] || continue
		vendor=${d%/}; vendor=${vendor##*/}
		files=$(ls "$d"*.bin 2>/dev/null | wc -l)
		printf '  %-14s %d dump(s)\n' "$vendor" "$files"
	done
}

show_bootrom() {
	[ -d "$BOOTROM_DIR" ] || die "BootROM dumps not bundled"
	found=0
	for f in "$BOOTROM_DIR"/*/"$1"*.bin "$BOOTROM_DIR"/"$1"*.bin; do
		[ -f "$f" ] || continue
		printf '  %-30s %6d KiB\n' "${f##*/}" "$(( $(wc -c < "$f") / 1024 ))"
		found=1
	done
	[ $found = 1 ] || msg "no dump matching '$1'"
}

# --- eng root --------------------------------------------------------------

engroot_check() {
	pick_device
	mfg=$(prop ro.product.manufacturer | tr -d '\r')
	soc_mfg=$(prop ro.soc.manufacturer | tr -d '\r')
	soc_model=$(prop ro.soc.model | tr -d '\r')
	platform=$(prop ro.board.platform | tr -d '\r')
	api=$(prop ro.build.version.sdk | tr -d '\r')
	bl_state=$(prop ro.boot.vbmeta.device_state | tr -d '\r')
	vb=$(prop ro.boot.verifiedbootstate | tr -d '\r')

	msg "SoC:        $soc_mfg $soc_model ($platform)"
	msg "bootloader: $bl_state"
	msg "verified:   $vb"
	echo

	if [ "$bl_state" = unlocked ]; then
		msg "bootloader is already unlocked."
		msg "standard root methods (Magisk/KernelSU/APatch) via patched boot.img work."
		return 0
	fi

	msg "bootloader is locked. engineering root methods by SoC vendor:"
	echo
	case $(echo "$soc_mfg" | tr '[:upper:]' '[:lower:]') in
	qualcomm|qcom)
		msg "  Qualcomm:"
		msg "    - EDL (9008): write custom programmer to unlock. Needs a firehose loader for this chipset."
		msg "    - Some older SoCs (MSM8916, MSM8937, MSM8953): CVE-based exploits exist."
		msg "    - Check if the BootROM dump is bundled: fb eng bootrom $(echo "$platform" | tr '[:upper:]' '[:lower:]')"
		;;
	mediatek|mtk)
		msg "  MediaTek:"
		msg "    - BROM exploit (mtkclient / penumbra): many SoCs are vulnerable to Kamakiri/Kamakiri2."
		msg "    - DA bypass: some chipsets allow writing without auth DA."
		msg "    - fb mtk unlock  (for penumbra-supported devices)"
		msg "    - fb mtk mtk da seccfg unlock  (for mtkclient-supported devices)"
		;;
	samsung|exynos)
		msg "  Samsung/Exynos:"
		msg "    - exynos-usbdl: BootROM USB download exploit on some Exynos SoCs."
		msg "    - odin4 flash: needs an unlocked bootloader first."
		msg "    - Samsung's own OEM unlock: region-dependent, often blocked."
		;;
	unisoc|spreadtrum)
		msg "  Unisoc/Spreadtrum:"
		msg "    - spd_dump / sfd_tool: flash over download mode."
		msg "    - Some SoCs have unprotected download mode, flash a stock boot with root baked in."
		;;
	*)
		msg "  SoC vendor '$soc_mfg' not specifically covered."
		;;
	esac
	echo
	msg "fb eng unlock  shows what the wall-of-shame DB says about this brand/model."
}

# --- dispatch -------------------------------------------------------------

cmd=$1
[ -n "$cmd" ] && shift
while [ $# -gt 0 ]; do
	take_serial "$@" && { [ "$1" = -s ] && shift; shift; continue; }
	break
done
case $cmd in
	''|-h|--help) usage ;;
	unlock)  need_root; unlock_lookup ;;
	brands)  list_brands ;;
	brand)   show_brand "$1" ;;
	bootroms) list_bootroms ;;
	bootrom) show_bootrom "$1" ;;
	engroot) need_root; engroot_check ;;
	*) usage; exit 1 ;;
esac
