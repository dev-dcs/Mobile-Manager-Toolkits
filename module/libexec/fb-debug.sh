#!/system/bin/sh
# fb debug - debugging helpers for the device on the other end of the cable
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

usage() {
	cat <<EOF
fb debug <command> [-s serial] [args]

  logcat [args]          live logcat, extra args go straight to logcat
  crash                  app crashes, ANRs, tombstones (more with root on target)
  boot                   boot reason, boot timing, last kernel log (root)
  selinux [-f file]      avc denials turned into allow rules
  app <package>          package details, memory, its recent log
  snapshot [name]        save props, settings, packages, services
  diff <a> <b>           what changed between two snapshots
  screen [file.png]      screenshot
  record [sec] [file]    screen recording, default 30 s
  bugreport [dir]        full bugreport zip
  shell [cmd]            adb shell

files go to $FB_OUT/
EOF
}

sub=$1
[ -n "$sub" ] && shift
args=""
while [ $# -gt 0 ]; do
	take_serial "$@" && { [ "$1" = -s ] && shift; shift; continue; }
	args="$args $(printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")")"
	shift
done
eval "set -- $args"

case $sub in ''|-h|--help) usage; exit 0 ;; esac
need_root
pick_device

case $sub in
logcat)
	if [ $# -eq 0 ]; then A logcat -v threadtime; else A logcat "$@"; fi
	;;

crash)
	out=$FB_OUT/crash/$SERIAL-$(stamp)
	mkdir -p "$out"
	ash logcat -b crash -d -v threadtime > "$out/logcat-crash.txt"
	ash dumpsys dropbox --print data_app_crash system_app_crash data_app_anr system_app_anr \
		SYSTEM_TOMBSTONE data_app_native_crash system_server_crash > "$out/dropbox.txt" 2>/dev/null
	if target_has_su; then
		A exec-out "su -c 'tar -cf - /data/tombstones /data/anr 2>/dev/null'" < /dev/null > "$out/tombstones-anr.tar"
	fi
	j=$(grep -c 'FATAL EXCEPTION' "$out/logcat-crash.txt")
	n=$(grep -c '^\*\*\* \*\*\* \*\*\*' "$out/logcat-crash.txt")
	a=$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]+ [a-z_]*_anr ' "$out/dropbox.txt")
	msg "java crashes $j, native crashes $n, ANRs in dropbox $a"
	sed -n 's/.*Process: \([^,]*\),.*/\1/p' "$out/logcat-crash.txt" | sort | uniq -c | sort -rn | head -n 10
	msg "$out"
	;;

boot)
	for k in ro.boot.bootreason sys.boot.reason sys.boot.reason.last persist.sys.boot.reason.history ro.boottime.init sys.boot_completed; do
		printf '  %-34s %s\n' "$k" "$(prop "$k" | tr '\n' ' ')"
	done
	msg "boot progress (ms since start):"
	ash logcat -b events -d | tr -d '\r' | grep -E 'boot_progress_|sf_stop_bootanim|wm_boot_animation_done' |
		awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^boot_|^sf_|^wm_/) { e = $i; v = $(i + 1); gsub(/[:\[\]]/, "", v); printf "  %-34s %s\n", e, v } }' | tail -n 20
	if target_has_su; then
		out=$FB_OUT/boot/$SERIAL-$(stamp)
		mkdir -p "$out"
		asu 'cat /sys/fs/pstore/console-ramoops* 2>/dev/null' > "$out/last_kmsg.txt"
		asu dmesg > "$out/dmesg.txt"
		msg "pstore + dmesg: $out"
	fi
	;;

selinux)
	src=""
	[ "$1" = -f ] && src=$2
	if [ -n "$src" ]; then
		log=$(cat "$src")
	else
		log=$(ash logcat -b all -d | tr -d '\r' | grep 'avc: *denied')
		target_has_su && log="$log
$(asu dmesg | tr -d '\r' | grep 'avc: *denied')"
	fi
	echo "$log" | grep 'avc: *denied' | awk '
		{
			if (!match($0, /\{[^}]*\}/)) next
			perms = substr($0, RSTART + 1, RLENGTH - 2)
			s = t = c = ""
			n = split($0, w, " ")
			for (i = 1; i <= n; i++) {
				if (w[i] ~ /^scontext=/) { split(w[i], a, ":"); s = a[3] }
				else if (w[i] ~ /^tcontext=/) { split(w[i], a, ":"); t = a[3] }
				else if (w[i] ~ /^tclass=/) c = substr(w[i], 8)
			}
			if (s == "" || t == "" || c == "") next
			if (t == s) t = "self"
			k = s " " t ":" c
			np = split(perms, p, " ")
			for (j = 1; j <= np; j++) if (p[j] != "" && !((k, p[j]) in seen)) {
				seen[k, p[j]] = 1
				acc[k] = acc[k] " " p[j]
			}
		}
		END { for (k in acc) printf "allow %s {%s };\n", k, acc[k] }' | sort
	;;

app)
	pkg=$1
	[ -n "$pkg" ] || die "fb debug app <package>"
	info=$(ash dumpsys package "$pkg" | tr -d '\r')
	echo "$info" | grep -q "Package \[$pkg\]" || die "$pkg is not installed"
	echo "$info" | grep -E '^ +(versionName|versionCode|targetSdk|firstInstallTime|lastUpdateTime|installerPackageName|userId|codePath|dataDir|pkgFlags)=' | sed 's/^ */  /' | sort -u
	pid=$(ash pidof "$pkg" | tr -d '\r')
	if [ -n "$pid" ]; then
		msg "  pid $pid"
		ash dumpsys meminfo "$pkg" | tr -d '\r' | grep -E 'TOTAL( PSS)?:' | head -n 1 | sed 's/^ */  /'
		msg "last log lines:"
		ash logcat -d -v brief --pid="$pid" | tail -n 40
	else
		msg "  not running"
		ash logcat -d -v brief | grep -F "$pkg" | tail -n 20
	fi
	;;

snapshot)
	name=${1:-$(stamp)}
	out=$FB_OUT/snapshots/$SERIAL/$name
	mkdir -p "$out"
	ash getprop > "$out/props.txt"
	for ns in system secure global; do ash settings list $ns > "$out/settings-$ns.txt"; done
	ash pm list packages -U --show-versioncode | sort > "$out/packages.txt"
	ash service list | sed 's/^[0-9]*[[:space:]]*//' | sort > "$out/services.txt"
	ash cat /proc/mounts > "$out/mounts.txt"
	sed -i 's/\r$//' "$out"/*.txt
	msg "snapshot $name -> $out"
	;;

diff)
	[ $# -eq 2 ] || die "fb debug diff <snapshot a> <snapshot b>"
	base=$FB_OUT/snapshots/$SERIAL
	[ -d "$base/$1" ] && [ -d "$base/$2" ] || die "unknown snapshot, have: $(ls "$base" 2>/dev/null | tr '\n' ' ')"
	for f in "$base/$1"/*.txt; do
		n=${f##*/}
		d=$(diff -U 0 "$f" "$base/$2/$n" 2>/dev/null | grep -E '^[+-][^+-]')
		[ -n "$d" ] && { msg "== $n"; echo "$d"; }
	done
	;;

screen)
	f=${1:-$FB_OUT/screens/$SERIAL-$(stamp).png}
	mkdir -p "${f%/*}"
	A exec-out screencap -p < /dev/null > "$f" && msg "$f"
	;;

record)
	sec=${1:-30}
	f=${2:-$FB_OUT/screens/$SERIAL-$(stamp).mp4}
	mkdir -p "${f%/*}"
	tmp=/data/local/tmp/fb-rec-$$.mp4
	msg "recording ${sec}s"
	ash screenrecord --time-limit "$sec" "$tmp"
	A pull "$tmp" "$f" >/dev/null && ash rm -f "$tmp"
	msg "$f"
	;;

bugreport)
	d=${1:-$FB_OUT/bugreports}
	mkdir -p "$d"
	A bugreport "$d/" && msg "$d"
	;;

shell)
	if [ $# -eq 0 ]; then A shell; else A shell "$@"; fi
	;;

*) usage; exit 1 ;;
esac
