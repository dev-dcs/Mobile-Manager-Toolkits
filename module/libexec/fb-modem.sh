#!/system/bin/sh
# fb modem - modem / baseband toolkit for the device on the other end
# Qualcomm NV + EFS over DIAG (qcdiag), AT consoles (atcmd), carrier config,
# MBN carrier profiles (mtools), and backup/restore of the modem partitions.
# Device identities (IMEI, MEID, ESN) are never written and backups only go
# back onto the phone they came from.
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

usage() {
	cat <<EOF
fb modem <command> [-s serial]

  info                         baseband, RIL, SIM/service state, bands in use
  backup                       image modem/EFS/NV partitions (rooted target)
  restore <dir> [-p a,b]       put such a backup back on the same phone

  at [-p port] <cmd>...        AT through the target's own modem port (root)
  at -l <tty|vid:pid> <cmd>... AT to a modem plugged into this phone

  diag on|off                  Qualcomm: expose the DIAG port over USB (root)
  nv read <id>                 Qualcomm NV item over DIAG
  nv write <id> <hex>...       old value saved first
  efs ls|stat|get <path>       Qualcomm EFS over DIAG
  efs put <path> <file>        old file saved first
  bands                        LTE / NR band preferences, decoded
  bands set lte|sa|nsa <list>  e.g. bands set lte 1,3,7,20,28

  carrier get [key]            carrier config of the active SIM
  carrier set <key> <value>    override one value (persists)
  carrier ims on               VoLTE / VoWiFi / video calling overrides
  carrier reset                drop every override

  mbn pull                     MBN carrier profiles from the target (root)
  mbn list <modem.img>         MBNs inside a modem (NON-HLOS) image
  mbn extract <modem.img> [dir]
  mbn replace <modem.img> <::/path/in/image> <file>

DIAG options (nv, efs, bands): -u vid:pid, -d /dev/ttyUSBx, -i iface
EOF
}

MODEM_PARTS='modem modemst1 modemst2 fsg fsc fsc_a fsc_b efs efs_backup efs_config sec_efs
persist cpefs nvdata nvram nvcfg protect1 protect2 protect_f protect_s md1img md1dsp
md1arm7 md3img proinfo l_fixnv1 l_fixnv2 l_runtimenv1 l_runtimenv2 prodnv mdm1m9kefs1
mdm1m9kefs2 mdm1m9kefs3 mdm1m9kefsc modem_userdata mdtp'

BAND_DIR=/nv/item_files/modem/mmode

QC=""
qc() {
	# shellcheck disable=SC2086
	qcdiag $QC "$@"
}

# ---- info ------------------------------------------------------------

info() {
	pick_device
	row() { printf '  %-12s %s\n' "$1" "$2"; }
	row baseband "$(prop gsm.version.baseband)"
	row ril "$(prop gsm.version.ril-impl)"
	row soc "$(prop ro.soc.manufacturer) $(prop ro.soc.model)"
	row sim "$(prop gsm.sim.state)"
	row operator "$(prop gsm.operator.alpha) ($(prop gsm.sim.operator.alpha))"
	row network "$(prop gsm.network.type)"

	reg=$(ash dumpsys telephony.registry | tr -d '\r')
	v=$(echo "$reg" | grep -oE 'mVoiceRegState=[0-9]+\([A-Z_]+\)' | head -n 1 | sed 's/.*(\(.*\))/\1/')
	d=$(echo "$reg" | grep -oE 'mDataRegState=[0-9]+\([A-Z_]+\)' | head -n 1 | sed 's/.*(\(.*\))/\1/')
	row service "voice ${v:-?}, data ${d:-?}"
	b=$(echo "$reg" | grep -oE 'CellIdentity(Lte|Nr):\{[^}]*' | while read -r c; do
		t=$(echo "$c" | sed -n 's/^CellIdentity\([A-Za-z]*\).*/\1/p')
		echo "$c" | grep -oE 'mBands ?= ?\[[0-9, ]*\]' | sed "s/.*\[\(.*\)\]/$t \1/"
	done | sort -u | tr '\n' ';')
	row bands "${b:-unknown}"

	if target_has_su; then
		bn=$(target_byname)
		have=$(target_parts "$bn" | awk -v want="$MODEM_PARTS" '
			BEGIN { n = split(want, w, /[ \n]+/); for (i = 1; i <= n; i++) ok[w[i]] = 1 }
			{ p = $1; sub(/_[ab]$/, "", p); if (p in ok) printf "%s ", $1 }')
		row partitions "$have"
		ports=$(asu 'ls /dev/smd7 /dev/smd11 /dev/at_mdm0 /dev/umts_atc0 /dev/umts_router /dev/nr_atc0 /dev/radio/pttycmd1 /dev/radio/atci1 /dev/ttyC0 /dev/stty_lte0 2>/dev/null' | tr -d '\r' | tr '\n' ' ')
		row "AT ports" "${ports:-none found}"
	fi
}

# ---- backup / restore -------------------------------------------------

backup() {
	pick_device
	target_has_su || die "backup needs su on the target"
	bn=$(target_byname)
	list=$(target_parts "$bn" | awk -v want="$MODEM_PARTS" '
		BEGIN { n = split(want, w, /[ \n]+/); for (i = 1; i <= n; i++) ok[w[i]] = 1 }
		{ p = $1; sub(/_[ab]$/, "", p); if (p in ok) print $1 }' | tr '\n' ',')
	[ -n "$list" ] || die "no modem partitions recognised on this target"
	msg "imaging: $list"
	sh "${0%/*}/fb-forensic.sh" image -s "$SERIAL" -p "${list%,}" -o "$FB_OUT/modem/backup"
}

restore() {
	dir=$1; shift
	only=""
	[ "$1" = -p ] && only=$(echo "$2" | tr ',' ' ')
	[ -f "$dir/acquisition.log" ] && [ -f "$dir/SHA256SUMS" ] || die "not a FlashBench backup: $dir"
	sh "${0%/*}/fb-forensic.sh" verify "$dir" || die "backup does not verify, not using it"

	from=$(sed -n 's/.*target=\([^,]*\),.*/\1/p' "$dir/acquisition.log" | head -n 1)
	parts=${only:-$(ls "$dir" | sed -n 's/\.img$//p')}

	if fastboot devices 2>/dev/null | grep -q .; then
		s=$(fastboot devices | awk '{print $1; exit}')
		# restoring EFS/NV of another phone clones its identity, never do that
		[ "$s" = "$from" ] || die "backup is from $from, fastboot device is $s"
		confirm "flash $parts from $dir with fastboot?" || die "stopped"
		for p in $parts; do
			fastboot -s "$s" flash "$p" "$dir/$p.img" || die "$p failed"
		done
		msg "done, reboot the target when ready"
		return
	fi

	pick_device
	[ "$SERIAL" = "$from" ] || die "backup is from $from, this target is $SERIAL"
	target_has_su || die "restore over adb needs su (or put the target in fastboot)"
	warn "the running modem can write its EFS back over this, fastboot is the safer way"
	confirm "write $parts back to $SERIAL and reboot it?" || die "stopped"
	bn=$(target_byname)
	for p in $parts; do
		want=$(awk -v f="$p.img" '$2 == f { print $1 }' "$dir/SHA256SUMS")
		A exec-in "su -c 'dd of=$bn/$p bs=1048576 conv=fsync 2>/dev/null'" < "$dir/$p.img"
		got=$(asu "head -c $(wc -c < "$dir/$p.img") $bn/$p | sha256sum" | cut -d' ' -f1)
		if [ "$got" = "$want" ]; then msg "  $p ok"; else die "$p does not read back the same"; fi
	done
	A reboot
	msg "restored, target is rebooting"
}

# ---- AT ----------------------------------------------------------------

at_cmd() {
	if [ "$1" = -l ]; then
		where=$2; shift 2
		[ $# -gt 0 ] || die "fb modem at -l <tty|vid:pid> <command>..."
		case $where in
			/dev/*) atcmd -d "$where" "$@" ;;
			*:*) atcmd -u"$where" "$@" ;;
			*) die "give a /dev path or vid:pid" ;;
		esac
		return
	fi

	port=""
	[ "$1" = -p ] && { port=$2; shift 2; }
	[ $# -gt 0 ] || die "fb modem at [-p port] <command>..."
	pick_device
	target_has_su || die "the target's modem ports need su"
	if [ -z "$port" ]; then
		port=$(asu 'for p in /dev/umts_atc0 /dev/nr_atc0 /dev/smd11 /dev/smd7 /dev/at_mdm0 /dev/radio/pttycmd1 /dev/radio/atci1 /dev/ttyC0 /dev/stty_lte0; do [ -c $p ] && { echo $p; break; }; done' | tr -d '\r')
		[ -n "$port" ] || die "no AT port found, try -p /dev/..."
	fi
	msg "# $port (the RIL may be using it too)"
	for c in "$@"; do
		b=$(printf %s "$c" | base64 | tr -d '\n')
		asu "exec 3<>$port; { printf %s $b | base64 -d; printf \"\\r\"; } >&3; timeout 3 cat <&3" |
			tr -d '\r' | grep -v '^$' | grep -vxF "$c"
	done
}

# ---- DIAG mode ---------------------------------------------------------

diag_mode() {
	pick_device
	target_has_su || die "switching USB functions needs su on the target"
	state=$FB_DATA/diag-prev-$SERIAL
	mkdir -p "$FB_DATA"
	case $1 in
	on)
		[ -f "$state" ] || prop sys.usb.config > "$state"
		for c in diag,serial_cdev,rmnet,dpl,adb diag,serial_cdev,rmnet,adb diag,adb; do
			asu "setprop sys.usb.config $c" >/dev/null
			sleep 4
			A wait-for-device 2>/dev/null
			[ "$(prop sys.usb.state)" = "$c" ] && { msg "DIAG on ($c), check fb usb"; return 0; }
		done
		die "the target did not take any DIAG config (non-Qualcomm, or the HAL refuses)"
		;;
	off)
		prev=$(cat "$state" 2>/dev/null)
		asu "setprop sys.usb.config ${prev:-mtp,adb}" >/dev/null
		rm -f "$state"
		msg "USB back to ${prev:-mtp,adb}"
		;;
	*) die "fb modem diag on|off" ;;
	esac
}

# ---- NV / EFS ----------------------------------------------------------

bk_dir() {
	d=$FB_OUT/modem/diag-backup/$(stamp)
	mkdir -p "$d"
	echo "$d"
}

nv() {
	case $1 in
	read) qc nv read "$2" ;;
	write)
		id=$2; shift 2
		[ -n "$id" ] && [ $# -gt 0 ] || die "fb modem nv write <id> <hex>..."
		case $((id)) in 0|550|1943) die "NV $id is a device identity (ESN/IMEI/MEID), not writable here" ;; esac
		d=$(bk_dir)
		qc nv read "$id" > "$d/nv-$id.txt" 2>&1
		msg "old value of $id:"
		cat "$d/nv-$id.txt"
		confirm "write NV $id = $*?" || die "stopped"
		qc nv write "$id" "$@" || die "write failed, nothing changed"
		msg "old value kept in $d"
		;;
	*) die "fb modem nv read|write ..." ;;
	esac
}

efs_backup_one() {
	f=$1/$(echo "$2" | sed 's|^/||; s|/|_|g')
	if qc efs get "$2" "$f" 2>/dev/null; then
		echo "$f"
	else
		rm -f "$f"
	fi
}

efs() {
	case $1 in
	ls|stat|get) qc efs "$@" ;;
	put)
		[ -f "$3" ] || die "fb modem efs put <path> <file>"
		d=$(bk_dir)
		old=$(efs_backup_one "$d" "$2")
		[ -n "$old" ] && msg "old file saved to $old" || msg "$2 does not exist yet"
		confirm "replace $2 with $3 ($(wc -c < "$3") bytes)?" || die "stopped"
		qc efs put "$2" "$3" || die "write failed"
		;;
	*) die "fb modem efs ls|stat|get|put ..." ;;
	esac
}

# bitmask file -> band numbers, bit 0 of byte 0 is band <base>
decode_bands() {
	od -An -v -t u1 "$1" | tr -s ' \n' '\n\n' | grep . | awk -v base="$2" '
		{ for (b = 0; b < 8; b++) if (int($1 / 2 ^ b) % 2) printf "%d ", base + (NR - 1) * 8 + b }'
}

# encode <bytes> <base> <list> -> file content on stdout
encode_bands() {
	echo "$3" | tr ',' '\n' | awk -v n="$1" -v base="$2" '
		/^[0-9]+$/ {
			i = $1 - base
			if (i < 0 || i >= n * 8) { print "band " $1 " does not fit" > "/dev/stderr"; bad = 1; next }
			v[int(i / 8)] += 2 ^ (i % 8)
		}
		END {
			if (bad) exit 1
			for (k = 0; k < n; k++) printf "\\%03o", v[k]
		}'
}

bands() {
	case $1 in
	''|show)
		t=${TMPDIR:-/data/local/tmp}/fb.bands.$$
		mkdir -p "$t"
		for spec in lte_bandpref:1:LTE lte_bandpref_extn_65_256:65:LTE nr5g_sa_bandpref:1:NR-SA nr5g_nsa_bandpref:1:NR-NSA; do
			f=${spec%%:*} rest=${spec#*:}
			base=${rest%%:*} label=${rest#*:}
			if qc efs get "$BAND_DIR/$f" "$t/$f" >/dev/null 2>&1; then
				printf '  %-8s %-26s %s\n' "$label" "$f" "$(decode_bands "$t/$f" "$base")"
			fi
		done
		rm -rf "$t"
		;;
	set)
		case $2 in
			lte) f=lte_bandpref base=1 ;;
			sa)  f=nr5g_sa_bandpref base=1 ;;
			nsa) f=nr5g_nsa_bandpref base=1 ;;
			*) die "fb modem bands set lte|sa|nsa <list>" ;;
		esac
		[ -n "$3" ] || die "band list missing, e.g. 1,3,7,20"
		d=$(bk_dir)
		old=$(efs_backup_one "$d" "$BAND_DIR/$f")
		[ -n "$old" ] || die "$BAND_DIR/$f not readable, is DIAG up? (fb modem diag on)"
		size=$(wc -c < "$old")
		new=$d/$f.new
		low=$3 high=""
		if [ "$2" = lte ]; then
			low=$(echo "$3" | tr ',' '\n' | awk '$1 >= 1 && $1 <= 64' | tr '\n' ',')
			high=$(echo "$3" | tr ',' '\n' | awk '$1 > 64' | tr '\n' ',')
		fi
		enc=$(encode_bands "$size" "$base" "$low") || die "band list does not fit $f ($size bytes)"
		# shellcheck disable=SC2059
		printf "$enc" > "$new"
		msg "$f now:  $(decode_bands "$old" "$base")"
		msg "$f new:  $(decode_bands "$new" "$base")"
		ext=""
		if [ -n "$high" ]; then
			eold=$(efs_backup_one "$d" "$BAND_DIR/lte_bandpref_extn_65_256")
			[ -n "$eold" ] || die "bands above 64 need lte_bandpref_extn_65_256, not on this modem"
			enc=$(encode_bands "$(wc -c < "$eold")" 65 "$high") || die "band list does not fit"
			ext=$d/lte_bandpref_extn_65_256.new
			# shellcheck disable=SC2059
			printf "$enc" > "$ext"
			msg "extn new: $(decode_bands "$ext" 65)"
		fi
		confirm "write the new band preference? (backup in $d)" || die "stopped"
		qc efs put "$BAND_DIR/$f" "$new" || die "write failed, old file is in $d"
		[ -n "$ext" ] && { qc efs put "$BAND_DIR/lte_bandpref_extn_65_256" "$ext" || die "extn write failed"; }
		msg "done, reboot the target so the modem reloads it"
		;;
	*) die "fb modem bands [show] | set lte|sa|nsa <list>" ;;
	esac
}

# ---- carrier config ----------------------------------------------------

IMS_KEYS='carrier_volte_available_bool=true
carrier_vt_available_bool=true
carrier_wfc_ims_available_bool=true
carrier_volte_provisioning_required_bool=false
editable_enhanced_4g_lte_bool=true
hide_enhanced_4g_lte_bool=false
editable_wfc_mode_bool=true
carrier_wfc_supports_wifi_only_bool=true
vonr_enabled_bool=true
vonr_setting_visibility_bool=true'

# cmd phone as shell first, root if the build refuses shell
phone_cc() {
	out=$(ash cmd phone cc "$@" 2>&1)
	case $out in
		*rror*|*ermission*|*ecurity*|*not\ allowed*)
			target_has_su && out=$(asu "cmd phone cc $*" 2>&1) ;;
	esac
	echo "$out" | tr -d '\r'
}

carrier() {
	pick_device
	case $1 in
	get) shift; phone_cc get-value "$@" ;;
	set)
		[ $# -eq 3 ] || die "fb modem carrier set <key> <value>"
		phone_cc set-value -p "$2" "$3"
		phone_cc get-value "$2"
		;;
	ims)
		[ "$2" = on ] || die "fb modem carrier ims on (off = carrier reset)"
		echo "$IMS_KEYS" | while IFS='=' read -r k v; do
			printf '  %-44s ' "$k"
			phone_cc set-value -p "$k" "$v" | tail -n 1
		done
		msg "toggle airplane mode or reboot so IMS registers again"
		;;
	reset) phone_cc clear-values && msg "overrides cleared" ;;
	*) die "fb modem carrier get|set|ims|reset" ;;
	esac
}

# ---- MBN ---------------------------------------------------------------

mt() { MTOOLS_SKIP_CHECK=1 mtools -c "$@"; }

mbn() {
	case $1 in
	pull)
		pick_device
		target_has_su || die "the modem firmware mount needs su"
		out=$FB_OUT/modem/mbn-$SERIAL-$(stamp)
		mkdir -p "$out"
		A exec-out "su -c 'cd /vendor/firmware_mnt/image && tar -cf - modem_pr/mcfg 2>/dev/null'" < /dev/null > "$out/mcfg.tar"
		(cd "$out" && tar -xf mcfg.tar && rm -f mcfg.tar)
		msg "$(find "$out" -name '*.mbn' | wc -l) MBN files in $out"
		;;
	list)
		[ -f "$2" ] || die "fb modem mbn list <modem.img>"
		mt mdir -/ -b -i "$2" ::/ | grep -i '\.mbn$'
		;;
	extract)
		[ -f "$2" ] || die "fb modem mbn extract <modem.img> [dir]"
		out=${3:-$FB_OUT/modem/mbn-$(basename "$2" .img)}
		mkdir -p "$out"
		mt mcopy -s -n -i "$2" ::/image/modem_pr/mcfg "$out/" || die "no image/modem_pr/mcfg in $2"
		msg "$(find "$out" -name '*.mbn' | wc -l) MBN files in $out"
		;;
	replace)
		[ -f "$2" ] && [ -f "$4" ] || die "fb modem mbn replace <modem.img> <::/path> <file>"
		case $3 in ::/*) ;; *) die "path inside the image starts with ::/" ;; esac
		cp "$2" "$2.orig" 2>/dev/null && msg "original kept as $2.orig"
		mt mcopy -o -i "$2" "$4" "$3" || die "mcopy failed"
		msg "replaced $3, new image sha256 $(sha256sum "$2" | cut -d' ' -f1)"
		msg "some modems check MBN hashes; flash with: fastboot flash modem_<slot> $2"
		;;
	*) die "fb modem mbn pull|list|extract|replace" ;;
	esac
}

# ---- dispatch ----------------------------------------------------------

cmd=$1
[ -n "$cmd" ] && shift
rest=""
while [ $# -gt 0 ]; do
	if take_serial "$@"; then
		[ "$1" = -s ] && shift
		shift
		continue
	fi
	case $1 in
		-u) QC="$QC -u$2"; shift 2; continue ;;
		-d) QC="$QC -d $2"; shift 2; continue ;;
		-i) QC="$QC -i $2"; shift 2; continue ;;
	esac
	rest="$rest $(printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")")"
	shift
done
eval "set -- $rest"

case $cmd in
	''|-h|--help) usage; exit 0 ;;
esac
need_root
case $cmd in
	info) info ;;
	backup) backup ;;
	restore) [ -n "$1" ] || die "fb modem restore <dir>"; restore "$@" ;;
	at) at_cmd "$@" ;;
	diag) diag_mode "$1" ;;
	nv) nv "$@" ;;
	efs) efs "$@" ;;
	bands) bands "$@" ;;
	carrier) carrier "$@" ;;
	mbn) mbn "$@" ;;
	*) usage; exit 1 ;;
esac
