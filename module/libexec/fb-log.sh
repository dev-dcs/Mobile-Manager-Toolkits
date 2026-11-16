#!/system/bin/sh
# fb log - a logcat catcher for this phone. Keeps a rotating logcat on disk so a
# crash or a reboot that happened while you were not looking is still there to
# read. Runs locally (root), not against a cable device - that is what fb debug
# is for.
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

LOGDIR=$FB_DATA/logs
PIDFILE=$LOGDIR/logger.pid

usage() {
	cat <<EOF
fb log <command>

  start [-b bufs] [-g regex] [-r kb] [-n count]
                         start the rotating catcher in the background
                           -b  buffers (default main,system,crash)
                           -g  only keep lines matching this regex
                           -r  size of each file in KB   (default 4096)
                           -n  how many files to keep     (default 8)
  stop                   stop it
  status                 is it running, and how big the ring is
  tail [args]            follow the live log (args go to logcat)
  save [file]            dump the current ring buffer to a file
  crash [file]           dump just the crash buffer
  clear                  wipe the kernel log ring (logcat -c)
  boot on|off            start the catcher automatically on every boot

files live in $LOGDIR
EOF
}

running() {
	[ -f "$PIDFILE" ] || return 1
	_p=$(cat "$PIDFILE" 2>/dev/null)
	[ -n "$_p" ] && [ -d "/proc/$_p" ] && grep -q logcat "/proc/$_p/cmdline" 2>/dev/null
}

start() {
	bufs=main,system,crash grep='' rkb=4096 keep=8
	while [ $# -gt 0 ]; do
		case $1 in
			-b) bufs=$2; shift ;;
			-g) grep=$2; shift ;;
			-r) rkb=$2; shift ;;
			-n) keep=$2; shift ;;
			*) die "start: unexpected '$1'" ;;
		esac
		shift
	done
	need_root
	running && { msg "already running (pid $(cat "$PIDFILE"))"; return 0; }
	mkdir -p "$LOGDIR"
	# -r/-n/-f make logcat rotate on its own; the grep stage is optional.
	if [ -n "$grep" ]; then
		conf_set log_grep "$grep"
		logcat -b "$bufs" -v threadtime 2>/dev/null \
			| grep -E --line-buffered "$grep" \
			>> "$LOGDIR/filtered.log" 2>/dev/null &
	else
		conf_set log_grep ""
		logcat -b "$bufs" -v threadtime -r "$rkb" -n "$keep" -f "$LOGDIR/logcat.log" \
			>/dev/null 2>&1 &
	fi
	echo $! > "$PIDFILE"
	conf_set log_bufs "$bufs"
	msg "catcher started (pid $!), buffers $bufs -> $LOGDIR"
}

stop() {
	need_root
	if running; then
		kill "$(cat "$PIDFILE")" 2>/dev/null
		rm -f "$PIDFILE"
		msg "stopped"
	else
		rm -f "$PIDFILE"
		msg "was not running"
	fi
}

case ${1:-} in
	''|-h|--help) usage ;;
	start) shift; start "$@" ;;
	stop) stop ;;
	status)
		if running; then
			msg "running (pid $(cat "$PIDFILE")), buffers $(conf log_bufs)"
		else
			msg "stopped"
		fi
		[ -d "$LOGDIR" ] && { msg "ring: $(du -sh "$LOGDIR" 2>/dev/null | cut -f1) in $LOGDIR"; ls -1 "$LOGDIR" 2>/dev/null | sed 's/^/  /'; }
		;;
	tail) shift; need_root; logcat -v threadtime "$@" ;;
	save)
		need_root; mkdir -p "$FB_OUT"
		out=${2:-$FB_OUT/logcat-$(stamp).txt}
		logcat -d -v threadtime > "$out" 2>/dev/null && msg "$out"
		;;
	crash)
		need_root; mkdir -p "$FB_OUT"
		out=${2:-$FB_OUT/crash-$(stamp).txt}
		logcat -b crash -d -v threadtime > "$out" 2>/dev/null && msg "$out"
		;;
	clear) need_root; logcat -c && msg "cleared" ;;
	boot)
		case ${2:-} in
			on) conf_set log_boot 1; msg "catcher will start on boot" ;;
			off) conf_set log_boot 0; msg "boot catcher off" ;;
			*) msg "fb log boot on|off (now: $(conf log_boot || echo 0))" ;;
		esac
		;;
	*) die "unknown command '$1' (fb log -h)" ;;
esac
