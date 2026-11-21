#!/system/bin/sh
# fb forensic - evidence collection from a device connected over adb
# read-only on the target: nothing is pushed or installed there
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

usage() {
	cat <<EOF
fb forensic <command> [-s serial] [options]

  triage                 security / compromise check, report on screen + file
  acquire                logical acquisition into a case folder
      -o DIR             output root (default $FB_OUT/cases)
      -c CASE            case id
      -e NAME            examiner
      --bugreport        add a full bugreport (slow)
      --sdcard           pull all of /sdcard (big)
      --root             rooted target: system dbs, dmesg, tombstones, user CAs
      --app-data         rooted target: tar of /data/data too (very big)
  image                  raw partition images from a rooted target
      --list             show partitions and sizes
      -p a,b,c           these partitions
      --all              all of them except userdata
      --with-userdata    with --all, include userdata
      -o DIR             output root (default $FB_OUT/images)
  apps                   installed apps: version, installer, install/update time
  verify DIR             re-hash a case or image folder against SHA256SUMS

Every case folder gets acquisition.log (what ran, when, exit code) and
SHA256SUMS over all collected files.
EOF
}

# --- case log helpers ---------------------------------------------------------

clog() { echo "$(now) $*" >> "$CASE/acquisition.log"; }

# cap <file> <command on target> : stdout to file, stderr kept next to it
cap() {
	f=$CASE/$1; shift
	mkdir -p "${f%/*}"
	A shell -T "$*" < /dev/null > "$f" 2> "$f.err"
	rc=$?
	[ -s "$f.err" ] || rm -f "$f.err"
	clog "rc=$rc size=$(wc -c < "$f") ${f#"$CASE"/} <- $*"
	printf '.'
	return 0
}

# binary safe stream through su on a rooted target
capsu() {
	f=$CASE/$1; shift
	mkdir -p "${f%/*}"
	A exec-out "su -c '$*'" < /dev/null > "$f"
	rc=$?
	clog "rc=$rc size=$(wc -c < "$f") ${f#"$CASE"/} <- su: $*"
	printf '.'
	return 0
}

hash_tree() {
	(cd "$1" && find . -type f ! -name SHA256SUMS ! -name acquisition.log \
		-exec sha256sum {} + | sed 's|  \./|  |' | sort -k 2) > "$1/SHA256SUMS"
}

# --- triage ------------------------------------------------------------------

triage() {
	pick_device
	mkdir -p "$FB_OUT/triage"
	rep=$FB_OUT/triage/$SERIAL-$(stamp).txt

	props=$(ash getprop | tr -d '\r')
	p() { echo "$props" | sed -n "s/^\[$1\]: \[\(.*\)\]$/\1/p"; }
	sec=$(ash settings list secure | tr -d '\r')
	glb=$(ash settings list global | tr -d '\r')
	s() { echo "$sec" | sed -n "s/^$1=//p"; }
	g() { echo "$glb" | sed -n "s/^$1=//p"; }

	{
		echo "FlashBench triage $(now)"
		echo "device  $(p ro.product.manufacturer) $(p ro.product.model) serial $SERIAL"
		echo "build   $(p ro.build.fingerprint)"
		echo "patch   $(p ro.build.version.security_patch)"
		echo

		flag() { printf '  [%s] %s\n' "$1" "$2"; }

		vb=$(p ro.boot.verifiedbootstate)
		[ "$vb" = green ] && flag ok "verified boot green" || flag '!' "verified boot: ${vb:-unknown}"
		ds=$(p ro.boot.vbmeta.device_state)
		[ "$ds" = locked ] && flag ok "bootloader locked" || flag '!' "bootloader: ${ds:-unknown}"
		se=$(ash getenforce | tr -d '\r')
		[ "$se" = Enforcing ] && flag ok "SELinux enforcing" || flag '!' "SELinux $se"
		case $(p ro.build.tags) in *test-keys*) flag '!' "test-keys build" ;; esac
		[ "$(p ro.debuggable)" = 1 ] && flag '!' "ro.debuggable=1"

		pk=$(ash pm list packages -U -i | tr -d '\r')
		for r in com.topjohnwu.magisk me.weishu.kernelsu me.bmax.apatch io.github.huskydg.magisk eu.chainfire.supersu; do
			echo "$pk" | grep -q "package:$r " && flag '!' "root manager installed: $r"
		done
		ash 'command -v su' >/dev/null 2>&1 && flag '!' "su binary in PATH"

		[ "$(g development_settings_enabled)" = 1 ] && flag i "developer options on"
		[ "$(g adb_wifi_enabled)" = 1 ] && flag '!' "wireless debugging on"
		port=$(p service.adb.tcp.port)
		[ -n "$port" ] && [ "$port" != -1 ] && [ "$port" != 0 ] && flag '!' "adb over tcp port $port"

		a=$(s enabled_accessibility_services)
		[ -n "$a" ] && [ "$a" != null ] && flag '!' "accessibility services: $a"
		n=$(s enabled_notification_listeners)
		[ -n "$n" ] && [ "$n" != null ] && flag i "notification listeners: $n"
		v=$(s always_on_vpn_app)
		[ -n "$v" ] && [ "$v" != null ] && flag i "always-on VPN: $v"

		admins=$(ash dumpsys device_policy | tr -d '\r' | awk '
			/Enabled Device Admins/ { on = 1; next }
			on && /^    [^ ].*:$/ { sub(/^ +/, ""); sub(/:$/, ""); print; next }
			/^  [^ ]/ { on = 0 }' | sort -u)
		[ -n "$admins" ] && echo "$admins" | while read -r l; do flag i "device admin: $l"; done

		for role in SMS DIALER ASSISTANT HOME BROWSER; do
			h=$(ash cmd role get-role-holders "android.app.role.$role" | tr -d '\r')
			[ -n "$h" ] && flag i "default $(echo $role | tr A-Z a-z): $h"
		done

		echo
		echo "  third-party apps not from Play:"
		ash pm list packages -3 -i | tr -d '\r' | while read -r l; do
			name=${l#package:}; name=${name%% *}
			inst=${l##*installer=}
			case $inst in com.android.vending|com.google.android.feedback) continue ;; esac
			perms=$(ash dumpsys package "$name" | tr -d '\r' | grep 'granted=true' |
				sed -n 's/^ *android\.permission\.\([A-Z_]*\): granted=true.*/\1/p' |
				grep -E '^(READ_SMS|RECEIVE_SMS|SEND_SMS|READ_CALL_LOG|RECORD_AUDIO|CAMERA|READ_CONTACTS|ACCESS_FINE_LOCATION|ACCESS_BACKGROUND_LOCATION|READ_PHONE_STATE|PROCESS_OUTGOING_CALLS)$' |
				sort -u | tr '\n' ' ')
			printf '    %-40s installer=%s\n' "$name" "$inst"
			[ -n "$perms" ] && printf '      sensitive: %s\n' "$perms"
		done

		if target_has_su; then
			echo
			echo "  target is rooted, extra checks:"
			cas=$(asu 'ls /data/misc/user/0/cacerts-added 2>/dev/null' | tr -d '\r')
			[ -n "$cas" ] && flag '!' "user CA certificates: $(echo "$cas" | tr '\n' ' ')"
			mods=$(asu 'ls /data/adb/modules 2>/dev/null' | tr -d '\r')
			[ -n "$mods" ] && flag i "root modules: $(echo "$mods" | tr '\n' ' ')"
		fi
	} | tee "$rep"
	msg
	msg "saved $rep"
}

# --- acquire -----------------------------------------------------------------

acquire() {
	root=$FB_OUT/cases case_id='' examiner='' bugrep=0 sdcard=0 useroot=0 appdata=0
	while [ $# -gt 0 ]; do
		take_serial "$@" && { [ "$1" = -s ] && shift; shift; continue; }
		case $1 in
			-o) root=$2; shift ;;
			-c) case_id=$2; shift ;;
			-e) examiner=$2; shift ;;
			--bugreport) bugrep=1 ;;
			--sdcard) sdcard=1 ;;
			--root) useroot=1 ;;
			--app-data) useroot=1 appdata=1 ;;
			*) die "unknown option $1" ;;
		esac
		shift
	done

	pick_device
	CASE=$root/${case_id:-case}-$SERIAL-$(stamp)
	mkdir -p "$CASE" || die "cannot create $CASE"

	clog "FlashBench forensic acquire, $(sed -n 's/^version=//p' "$FB_MOD/module.prop")"
	clog "case=${case_id:--} examiner=${examiner:--} target=$SERIAL"
	clog "host=$(getprop ro.product.model) $(getprop ro.build.fingerprint)"
	t_host=$(date -u +%s)
	t_dev=$(ash date -u +%s | tr -d '\r')
	clog "clock host=$t_host target=$t_dev skew=$((t_dev - t_host))s"
	msg "case: $CASE"

	printf 'device '
	cap device/getprop.txt getprop
	cap device/id.txt id
	cap device/uname.txt uname -a
	cap device/uptime.txt uptime
	cap device/date.txt date
	cap device/mounts.txt cat /proc/mounts
	cap device/df.txt df -h
	cap device/cpuinfo.txt cat /proc/cpuinfo
	cap device/meminfo.txt cat /proc/meminfo
	cap device/ip-addr.txt ip addr
	cap device/netstat.txt netstat -tuanW
	cap device/ps.txt ps -A -o USER,PID,PPID,STIME,TIME,NAME,ARGS
	cap device/services.txt service list
	cap device/users.txt pm list users
	cap device/features.txt pm list features
	for ns in system secure global; do cap "device/settings-$ns.txt" settings list $ns; done
	echo

	printf 'packages '
	cap packages/list.txt pm list packages -f -i -U --show-versioncode
	cap packages/third-party.txt pm list packages -3 -i
	cap packages/disabled.txt pm list packages -d
	cap packages/dumpsys-package.txt dumpsys package
	cap packages/appops.txt dumpsys appops
	echo

	printf 'dumpsys '
	for d in account accessibility activity alarm battery batterystats bluetooth_manager \
		connectivity device_policy jobscheduler location netstats notification power role \
		telephony.registry usagestats user wifi; do
		cap "dumpsys/$d.txt" dumpsys "$d"
	done
	echo

	printf 'logs '
	cap logs/logcat-all.txt logcat -b all -d -v threadtime -v UTC -v year
	cap logs/dropbox.txt dumpsys dropbox --print
	echo

	printf 'content '
	cap content/call_log.txt content query --uri content://call_log/calls
	cap content/sms.txt content query --uri content://sms
	cap content/mms.txt content query --uri content://mms
	cap content/contacts.txt content query --uri content://com.android.contacts/data
	cap content/calendar.txt content query --uri content://com.android.calendar/events
	cap content/media-files.txt content query --uri content://media/external/file --projection _id:_data:date_added:date_modified:mime_type:_size
	echo

	printf 'storage '
	cap storage/timeline.txt "find /sdcard/ -xdev -type f -exec stat -c '%s|%Y|%X|%Z|%n' {} +"
	echo

	if [ $useroot = 1 ]; then
		if target_has_su; then
			printf 'root '
			capsu root/dmesg.txt dmesg
			# exec-out has no separate stderr, keep tar warnings out of the archive
			capsu root/system.tar "tar -cf - /data/system /data/system_ce/0 /data/system_de/0 \
				/data/misc_ce/0 /data/misc_de/0 /data/misc/wifi /data/misc/bluedroid \
				/data/misc/user/0 /data/tombstones /data/anr 2>/dev/null"
			capsu root/data-adb.txt "ls -laR /data/adb 2>&1"
			[ $appdata = 1 ] && capsu root/data-data.tar "tar -cf - /data/data /data/user_de/0 2>/dev/null"
			echo
		else
			clog "skip root parts, su not granted on target"
			warn "target has no usable su, root parts skipped"
		fi
	fi

	if [ $bugrep = 1 ]; then
		msg "bugreport (takes a few minutes)"
		mkdir -p "$CASE/bugreport"
		A bugreport "$CASE/bugreport/" >/dev/null 2>&1
		clog "rc=$? bugreport/"
	fi

	if [ $sdcard = 1 ]; then
		msg "pulling /sdcard"
		mkdir -p "$CASE/storage/sdcard"
		A pull -a /sdcard/ "$CASE/storage/sdcard/" >/dev/null 2>&1
		clog "rc=$? storage/sdcard <- adb pull -a /sdcard/"
	fi

	{
		echo "case       ${case_id:--}"
		echo "examiner   ${examiner:--}"
		echo "target     $SERIAL $(sed -n 's/^\[ro.product.model\]: \[\(.*\)\]/\1/p' "$CASE/device/getprop.txt")"
		echo "android    $(sed -n 's/^\[ro.build.version.release\]: \[\(.*\)\]/\1/p' "$CASE/device/getprop.txt"), patch $(sed -n 's/^\[ro.build.version.security_patch\]: \[\(.*\)\]/\1/p' "$CASE/device/getprop.txt")"
		echo "clock skew $((t_dev - t_host))s (target - host)"
		echo "files      $(find "$CASE" -type f ! -name acquisition.log | wc -l)"
		echo "size       $(du -sh "$CASE" | cut -f1)"
		echo "denied     $(find "$CASE" -name '*.err' | wc -l) command(s) wrote errors, see *.err"
	} > "$CASE/report.txt"
	msg "hashing"
	hash_tree "$CASE"
	clog "SHA256SUMS $(sha256sum "$CASE/SHA256SUMS" | cut -d' ' -f1) files=$(grep -c . "$CASE/SHA256SUMS")"
	clog "done"

	cat "$CASE/report.txt"
}

# --- image ---------------------------------------------------------------------

image() {
	root=$FB_OUT/images parts='' all=0 udata=0 list=0
	while [ $# -gt 0 ]; do
		take_serial "$@" && { [ "$1" = -s ] && shift; shift; continue; }
		case $1 in
			-p) parts=$(echo "$2" | tr ',' ' '); shift ;;
			--all) all=1 ;;
			--with-userdata) udata=1 ;;
			--list) list=1 ;;
			-o) root=$2; shift ;;
			*) die "unknown option $1" ;;
		esac
		shift
	done
	pick_device
	target_has_su || die "imaging needs su on the target"

	bn=$(target_byname)
	[ -n "$bn" ] || die "no by-name partition folder found on target"
	table=$(target_parts "$bn")

	if [ $list = 1 ]; then
		echo "$table" | awk '{ printf "  %-28s %10.1f MiB\n", $1, $2 / 1048576 }'
		return 0
	fi

	if [ $all = 1 ]; then
		parts=$(echo "$table" | awk '{print $1}')
		[ $udata = 1 ] || parts=$(echo "$parts" | grep -vx userdata)
	fi
	[ -n "$parts" ] || die "nothing to image, use -p or --all (or --list)"

	CASE=$root/$SERIAL-$(stamp)
	mkdir -p "$CASE"
	clog "FlashBench forensic image, target=$SERIAL, by-name=$bn"
	clog "model=$(prop ro.product.model) device=$(prop ro.product.device)"
	clog "fingerprint=$(prop ro.build.fingerprint)"

	bad=0
	for p in $parts; do
		size=$(echo "$table" | awk -v p="$p" '$1 == p {print $2}')
		[ -n "$size" ] || { warn "$p: no such partition"; continue; }
		printf '  %-24s %8s MiB  ' "$p" "$((size / 1048576))"
		before=$(asu "sha256sum $bn/$p" | tr -d '\r' | cut -d' ' -f1)
		A exec-out "su -c 'cat $bn/$p 2>/dev/null'" < /dev/null > "$CASE/$p.img"
		got=$(sha256sum "$CASE/$p.img" | cut -d' ' -f1)
		have=$(wc -c < "$CASE/$p.img")
		if [ "$got" = "$before" ] && [ "$have" = "$size" ]; then
			echo ok
			clog "ok $p size=$size sha256=$got"
		else
			echo MISMATCH
			clog "MISMATCH $p size=$size got=$have target_sha256=$before local_sha256=$got (mounted rw?)"
			bad=$((bad + 1))
		fi
	done
	hash_tree "$CASE"
	clog "done, $bad mismatch(es)"
	msg "$CASE"
	[ $bad = 0 ]
}

# --- apps --------------------------------------------------------------------

apps() {
	while [ $# -gt 0 ]; do
		take_serial "$@" && { [ "$1" = -s ] && shift; shift; continue; }
		die "unknown option $1"
	done
	pick_device
	mkdir -p "$FB_OUT/apps"
	out=$FB_OUT/apps/$SERIAL-$(stamp).tsv

	ash dumpsys package packages | tr -d '\r' | awk '
		function flush() {
			if (pkg != "") print pkg "\t" vn "\t" vc "\t" inst "\t" first "\t" upd "\t" uid "\t" kind
			pkg = vn = vc = inst = first = upd = uid = ""; kind = "user"
		}
		BEGIN { print "package\tversion\tcode\tinstaller\tfirst_install\tlast_update\tuid\ttype" }
		/^  Package \[/ { flush(); pkg = $2; gsub(/[\[\]]/, "", pkg); next }
		/^    userId=/ { uid = substr($1, 8) }
		/^    versionCode=/ { vc = substr($1, 13) }
		/^    versionName=/ { vn = substr($0, index($0, "=") + 1) }
		/^    lastUpdateTime=/ { upd = substr($0, index($0, "=") + 1) }
		/^    installerPackageName=/ { inst = substr($0, index($0, "=") + 1) }
		/^    pkgFlags=\[.* SYSTEM / { kind = "system" }
		/firstInstallTime=/ && first == "" {
			s = substr($0, index($0, "firstInstallTime=") + 17)
			first = substr(s, 1, 19)
		}
		END { flush() }
	' > "$out"

	awk -F'\t' 'NR > 1 && $8 == "user" { printf "  %-42s %-14s %-24s %s\n", $1, substr($2, 1, 14), $4, $5 }' "$out"
	msg "$(($(wc -l < "$out") - 1)) packages, full table: $out"
}

# --- verify ------------------------------------------------------------------

verify() {
	[ -f "$1/SHA256SUMS" ] || die "no SHA256SUMS in ${1:-?}"
	if (cd "$1" && sha256sum -c SHA256SUMS >/dev/null 2>"$TMPDIR/fb.verify.$$" ); then
		msg "all $(grep -c . "$1/SHA256SUMS") files match"
		rm -f "$TMPDIR/fb.verify.$$"
	else
		(cd "$1" && sha256sum -c SHA256SUMS 2>/dev/null | grep -v ': OK$')
		rm -f "$TMPDIR/fb.verify.$$"
		die "integrity check failed"
	fi
}

TMPDIR=${TMPDIR:-/data/local/tmp}
cmd=$1
[ -n "$cmd" ] && shift
case $cmd in
	triage)
		while [ $# -gt 0 ]; do take_serial "$@" && { [ "$1" = -s ] && shift; shift; continue; }; die "unknown option $1"; done
		need_root; triage ;;
	acquire) need_root; acquire "$@" ;;
	image)   need_root; image "$@" ;;
	apps)    need_root; apps "$@" ;;
	verify)  verify "$1" ;;
	''|-h|--help) usage ;;
	*) usage; exit 1 ;;
esac
