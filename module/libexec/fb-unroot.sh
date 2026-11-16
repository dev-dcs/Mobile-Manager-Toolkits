#!/system/bin/sh
# fb unroot - take Magisk, KernelSU or APatch off a connected device and put
# its stock boot / init_boot back. Shows the plan, backs everything up to
# this phone first, and only acts after a typed "yes".
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

usage() {
	cat <<EOF
fb unroot [-s serial] [options]

  --stock-boot <img>        stock boot image for the target's build
  --stock-init-boot <img>   stock init_boot image
  --ota <ota.zip|payload>   take both from the matching full OTA
  --keep-apps               do not uninstall the root manager apps
  --partial                 clean userspace even if the patched image cannot be restored
  --dry-run                 show the plan and stop
  --yes                     no prompt
  --force                   flash even if the OTA fingerprint does not match

Over adb with working su: backup, stock images written and read back,
/data/adb wiped, manager apps removed, reboot.
Without su or in fastboot: manager apps removed (adb), stock images
flashed with fastboot.
Magisk keeps a stock copy on the device, so it often needs no image at all.
EOF
}

sboot='' sinit='' ota='' keep_apps=0 dry=0 force=0 partial=0 incomplete=0
while [ $# -gt 0 ]; do
	take_serial "$@" && { [ "$1" = -s ] && shift; shift; continue; }
	case $1 in
		--stock-boot) sboot=$2; shift ;;
		--stock-init-boot) sinit=$2; shift ;;
		--ota) ota=$2; shift ;;
		--keep-apps) keep_apps=1 ;;
		--dry-run) dry=1 ;;
		--partial) partial=1 ;;
		--yes) FB_YES=1 ;;
		--force) force=1 ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown option $1" ;;
	esac
	shift
done
for f in "$sboot" "$sinit" "$ota"; do
	[ -z "$f" ] || [ -f "$f" ] || die "no such file: $f"
done
need_root

MANAGERS='com.topjohnwu.magisk io.github.vvb2060.magisk io.github.huskydg.magisk
me.weishu.kernelsu com.rifsxd.ksunext com.sukisu.ultra me.bmax.apatch
eu.chainfire.supersu com.koushikdutta.superuser org.lsposed.manager'

W=${TMPDIR:-/data/local/tmp}/fb-unroot.$$
trap 'rm -rf "$W"' EXIT INT TERM
mkdir -p "$W"

plan=""
step() { plan="$plan
  $(printf '%2d' $(($(echo "$plan" | grep -c .) + 1))). $*"; }

img_ok() { [ "$(head -c 8 "$1" 2>/dev/null)" = "ANDROID!" ]; }

# ---- where are we ------------------------------------------------------

mode=""
if [ -n "$(adb_devices)" ]; then
	pick_device
	mode=adb
elif fastboot devices 2>/dev/null | grep -q .; then
	SERIAL=${SERIAL:-$(fastboot devices | awk '{print $1; exit}')}
	mode=fastboot
else
	die "no device over adb or fastboot"
fi

# ---- stock images from an OTA -------------------------------------------

if [ -n "$ota" ]; then
	pd=$(command -v payload-dumper-go || command -v fb-payload-dumper-go) || die "payload-dumper-go is not in this build"
	if [ $mode = adb ]; then
		want=$(prop ro.build.fingerprint)
		have=$(unzip -p "$ota" META-INF/com/android/metadata 2>/dev/null | sed -n 's/^post-build=//p')
		if [ -n "$have" ] && [ "$have" != "$want" ]; then
			[ $force = 1 ] || die "OTA is $have, target runs $want (--force to flash anyway)"
			warn "OTA fingerprint differs from the target, --force given"
		fi
	fi
	msg "extracting boot images from the OTA"
	"$pd" -o "$W/ota" -p boot,init_boot "$ota" >/dev/null 2>&1
	[ -z "$sboot" ] && [ -f "$W/ota/boot.img" ] && sboot=$W/ota/boot.img
	[ -z "$sinit" ] && [ -f "$W/ota/init_boot.img" ] && sinit=$W/ota/init_boot.img
fi
for f in "$sboot" "$sinit"; do
	[ -z "$f" ] || img_ok "$f" || die "$f is not a boot image"
done

# ---- fastboot only -----------------------------------------------------

if [ $mode = fastboot ]; then
	[ -n "$sboot$sinit" ] || die "in fastboot there is nothing to clean without stock images (--stock-boot / --stock-init-boot / --ota)"
	[ -n "$sboot" ] && step "fastboot flash boot $(basename "$sboot")"
	[ -n "$sinit" ] && step "fastboot flash init_boot $(basename "$sinit")"
	step "fastboot reboot"
	msg "plan for $SERIAL (fastboot):$plan"
	msg "/data/adb leftovers stay but do nothing without the patched images"
	[ $dry = 1 ] && exit 0
	confirm "go?" || die "stopped"
	[ -n "$sboot" ] && { fastboot -s "$SERIAL" flash boot "$sboot" || die "boot flash failed"; }
	[ -n "$sinit" ] && { fastboot -s "$SERIAL" flash init_boot "$sinit" || die "init_boot flash failed"; }
	fastboot -s "$SERIAL" reboot
	exit 0
fi

# ---- adb: what is installed --------------------------------------------

slot=$(prop ro.boot.slot_suffix)
pk=$(ash pm list packages | tr -d '\r' | sed 's/^package://')
apps=""
for p in $MANAGERS; do
	echo "$pk" | grep -qx "$p" && apps="$apps $p"
done

root=0 lkm=0 has_init=0 bn=""
target_has_su && root=1
kind="" magisk_bak="" hidden=""
if [ $root = 1 ]; then
	found=$(asu 'for p in /data/adb/magisk /data/adb/ksu /data/adb/ksud /data/adb/ap /data/adb/apd /data/adb/modules /system/xbin/su /system/bin/su; do [ -e $p ] && echo $p; done' | tr -d '\r')
	echo "$found" | grep -q '/data/adb/magisk' && kind="$kind magisk"
	echo "$found" | grep -qE '/data/adb/(ksu|ksud)' && kind="$kind kernelsu"
	echo "$found" | grep -qE '/data/adb/(ap|apd)$' && kind="$kind apatch"
	echo "$found" | grep -q '/system/' && kind="$kind system-su"

	if echo "$kind" | grep -q magisk; then
		hidden=$(asu 'magisk --sqlite "SELECT value FROM strings WHERE key=\"requester\""' | tr -d '\r' | sed -n 's/^value=//p')
		[ -n "$hidden" ] && apps="$apps $hidden"
		magisk_bak=$(asu 'ls -d /data/magisk_backup_* 2>/dev/null' | tr -d '\r' | head -n 1)
	fi
	asu 'grep -q "^kernelsu " /proc/modules' 2>/dev/null && lkm=1

	bn=$(target_byname)
	has_init=0
	asu "[ -e $bn/init_boot$slot ]" && has_init=1
fi

msg "target   $SERIAL $(prop ro.product.model), slot ${slot:-none}"
msg "root     ${kind:-$( [ $root = 1 ] && echo 'su works, solution unknown' || echo 'no working su')}"
msg "apps     ${apps:-none found}"

# ---- which image goes where ---------------------------------------------

w_boot="" w_init="" magisk_restore=""
if [ $root = 1 ]; then
	[ -n "$sboot" ] && w_boot=$sboot
	if [ -n "$sinit" ]; then
		[ $has_init = 1 ] && w_init=$sinit || warn "target has no init_boot partition, $(basename "$sinit") ignored"
	fi

	case $kind in
	*magisk*)
		if [ -z "$w_boot$w_init" ] && [ -n "$magisk_bak" ]; then
			# Magisk patches init_boot when the device has one, boot otherwise
			if [ $has_init = 1 ]; then magisk_restore=init_boot$slot; else magisk_restore=boot$slot; fi
		elif [ -z "$w_boot$w_init" ]; then
			warn "Magisk has no stock backup on the device, pass --stock-* or --ota"
			incomplete=1
		fi
		;;
	esac
	case $kind in
	*kernelsu*)
		if [ $lkm = 1 ] && [ $has_init = 1 ] && [ -z "$w_init" ]; then
			warn "KernelSU LKM patched init_boot: --stock-init-boot or --ota is needed to undo it"
			incomplete=1
		elif [ $lkm = 0 ] && [ -z "$w_boot" ]; then
			warn "KernelSU is built into the kernel: --stock-boot or --ota is needed, or root stays in the kernel"
			incomplete=1
		fi
		;;
	esac
	case $kind in
	*apatch*) [ -z "$w_boot" ] && { warn "APatch patched boot: --stock-boot or --ota is needed to undo it"; incomplete=1; } ;;
	esac

	out=$FB_OUT/unroot/$SERIAL-$(stamp)
	step "back up /data/adb, boot$slot$( [ $has_init = 1 ] && echo " and init_boot$slot") to $out"
	[ -n "$magisk_restore" ] && step "restore Magisk's own stock copy ($magisk_bak) to $magisk_restore, checked against its SHA1"
	[ -n "$w_boot" ] && step "write $(basename "$w_boot") to boot$slot and read it back"
	[ -n "$w_init" ] && step "write $(basename "$w_init") to init_boot$slot and read it back"
	step "delete /data/adb/*, /data/magisk_backup_*, /cache/magisk.log"
	echo "$kind" | grep -q system-su && step "remount /system and remove su from it (system-as-root, may fail)"
else
	warn "no working su on the target: /data/adb cannot be cleaned from here"
	if [ -n "$sboot$sinit" ]; then
		step "adb reboot bootloader"
		[ -n "$sboot" ] && step "fastboot flash boot $(basename "$sboot")"
		[ -n "$sinit" ] && step "fastboot flash init_boot $(basename "$sinit")"
	fi
fi
[ $keep_apps = 0 ] && [ -n "$apps" ] && step "uninstall:$apps"
step "reboot"

msg "plan:$plan"
[ $dry = 1 ] && exit 0
if [ $incomplete = 1 ] && [ $partial = 0 ]; then
	die "the patched boot image would stay, so root would only be half gone. Give the stock image (or --ota), or --partial to clean userspace anyway"
fi
confirm "this changes $SERIAL for real. go?" || die "stopped"

# ---- do it -------------------------------------------------------------

LOG=/dev/null
if [ $root = 1 ]; then
	mkdir -p "$out"
	LOG=$out/unroot.log
	echo "$(now) unroot $SERIAL kind=$kind" > "$LOG"
	msg "backup"
	A exec-out "su -c 'tar -cf - /data/adb 2>/dev/null'" < /dev/null > "$out/data-adb.tar"
	A exec-out "su -c 'cat $bn/boot$slot'" < /dev/null > "$out/boot$slot.img"
	[ $has_init = 1 ] && A exec-out "su -c 'cat $bn/init_boot$slot'" < /dev/null > "$out/init_boot$slot.img"
	ash pm list packages -U -i > "$out/packages.txt"
	(cd "$out" && sha256sum ./*.img ./*.tar > SHA256SUMS)
	echo "$(now) backup done" >> "$LOG"

	write_part() {
		part=$1 img=$2
		size=$(wc -c < "$img")
		want=$(sha256sum "$img" | cut -d' ' -f1)
		A exec-in "su -c 'dd of=$bn/$part bs=1048576 conv=fsync 2>/dev/null'" < "$img"
		got=$(asu "head -c $size $bn/$part | sha256sum" | cut -d' ' -f1)
		echo "$(now) wrote $part from $img sha256=$want readback=$got" >> "$LOG"
		[ "$got" = "$want" ] || die "$part did not read back right; your backup is in $out (flash it with fastboot)"
		msg "  $part ok"
	}

	if [ -n "$magisk_restore" ]; then
		sha=${magisk_bak##*_}
		f=$(asu "ls $magisk_bak/*.img.gz" | tr -d '\r' | head -n 1)
		got=$(asu "zcat $f | sha1sum" | cut -d' ' -f1)
		[ "$got" = "$sha" ] || die "Magisk's stock copy does not match its SHA1, nothing written"
		asu "zcat $f | dd of=$bn/$magisk_restore bs=1048576 conv=fsync 2>/dev/null"
		echo "$(now) restored $magisk_restore from $f sha1=$sha" >> "$LOG"
		msg "  $magisk_restore restored from Magisk's copy"
	fi
	[ -n "$w_boot" ] && write_part "boot$slot" "$w_boot"
	[ -n "$w_init" ] && write_part "init_boot$slot" "$w_init"

	if echo "$kind" | grep -q system-su; then
		asu 'mount -o rw,remount / 2>/dev/null; rm -f /system/xbin/su /system/bin/su; mount -o ro,remount / 2>/dev/null' ||
			warn "could not remove su from /system"
	fi
	asu 'rm -rf /data/adb/* /data/magisk_backup_* /cache/magisk.log 2>/dev/null; true'
	echo "$(now) /data/adb cleaned" >> "$LOG"
	msg "/data/adb cleaned"
fi

if [ $keep_apps = 0 ]; then
	for p in $apps; do
		r=$(ash pm uninstall "$p" | tr -d '\r')
		msg "  $p: $r"
		echo "$(now) uninstall $p: $r" >> "$LOG"
	done
fi

if [ $root = 0 ] && [ -n "$sboot$sinit" ]; then
	A reboot bootloader
	n=0
	until fastboot devices 2>/dev/null | grep -q "$SERIAL"; do
		n=$((n + 1)); [ $n -gt 60 ] && die "target did not show up in fastboot"
		sleep 1
	done
	[ -n "$sboot" ] && { fastboot -s "$SERIAL" flash boot "$sboot" || die "boot flash failed"; }
	[ -n "$sinit" ] && { fastboot -s "$SERIAL" flash init_boot "$sinit" || die "init_boot flash failed"; }
	fastboot -s "$SERIAL" reboot
else
	A reboot
fi
msg "done. after boot, check with: fb forensic triage"
[ $root = 1 ] && msg "backup: $out"
