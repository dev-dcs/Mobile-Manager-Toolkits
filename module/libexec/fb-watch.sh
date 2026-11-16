#!/system/bin/sh
# fb watch - checks the upstream repos of every bundled tool and tells you
# when one has a newer release than what this build was made from
# @Dev_DcS

. "${0%/*}/../lib/common.sh"
. "$FB_LIB/upstream.sh"

STATE=$FB_DATA/watch.state
SEEN=$FB_DATA/watch.seen
LOG=$FB_DATA/watch.log
PID=$FB_DATA/watch.pid

usage() {
	cat <<EOF
fb watch [option]

  --now              check right away and notify about anything new
  --status           last result (default)
  --on / --off       start or stop the background watcher
  --interval SEC     time between checks (now: $(conf watch_interval))
  --notify MODE      android, ntfy, both or none (now: $(conf notify))
  --ntfy URL         ntfy topic url for push to other devices
  --test             send a test notification
  --reset            forget what was already notified
EOF
}

log() { echo "$(now) $*" >> "$LOG"; }

check_now() {
	UP_FETCH=fb_fetch
	res=$(up_check_all "$FB_MOD/components.list")
	[ -n "$res" ] || { log "check failed, no network?"; return 1; }

	echo "$res" > "$STATE"
	now > "$STATE.time"

	errs=$(echo "$res" | grep -c '|error|')
	[ "$errs" -gt 0 ] && log "$errs repo(s) did not answer"

	pending=$(echo "$res" | awk -F'|' '$2 == "update" || $2 == "moved" { print $1, $4 }')
	if [ -n "$pending" ]; then
		set_status "$(echo "$pending" | grep -c .) upstream update(s): fb watch"
	else
		set_status ""
	fi

	fresh=$(echo "$pending" | while read -r n v; do
		[ -n "$n" ] || continue
		grep -qx "$n $v" "$SEEN" 2>/dev/null || echo "$n $v"
	done)
	[ -n "$fresh" ] || { log "checked, nothing new"; return 0; }

	body=$(echo "$fresh" | sed 's/ / -> /' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
	notify "FlashBench: upstream update" "$body. Time for a new master build."
	echo "$fresh" >> "$SEEN"
	log "notified: $body"
}

show_status() {
	if [ ! -f "$STATE" ]; then
		msg "no check done yet (fb watch --now)"
		return 0
	fi
	msg "last check $(cat "$STATE.time" 2>/dev/null), watcher $( [ "$(conf watch)" = 1 ] && echo on || echo off)"
	awk -F'|' '
		{ printf "  %-18s %-7s %-16s %s\n", $1, $2, $3, ($2 == "ok" ? "" : $4) }
		$2 == "held" { printf "  %-18s         %s\n", "", $5 }
	' "$STATE"
}

daemon() {
	if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
		exit 0
	fi
	echo $$ > "$PID"
	trap 'rm -f "$PID"' EXIT
	log "watcher started"
	while [ "$(conf watch)" = 1 ]; do
		check_now
		tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
		iv=$(conf watch_interval)
		sleep "${iv:-43200}"
	done
	log "watcher stopped"
}

need_root
mkdir -p "$FB_DATA"

case ${1:---status} in
	--now) check_now && show_status ;;
	--status) show_status ;;
	--daemon) daemon ;;
	--on)
		conf_set watch 1
		(sh "$0" --daemon </dev/null >/dev/null 2>&1 &)
		msg "watcher on"
		;;
	--off)
		conf_set watch 0
		[ -f "$PID" ] && kill "$(cat "$PID")" 2>/dev/null
		rm -f "$PID"
		set_status ""
		msg "watcher off"
		;;
	--interval) [ "$2" -ge 600 ] 2>/dev/null || die "interval in seconds, 600 or more"; conf_set watch_interval "$2" ;;
	--notify)
		case $2 in android|ntfy|both|none) conf_set notify "$2" ;; *) die "android, ntfy, both or none" ;; esac ;;
	--ntfy) conf_set ntfy_url "$2" ;;
	--test) notify "FlashBench" "test notification from fb watch" && msg sent ;;
	--reset) rm -f "$SEEN"; set_status ""; msg "cleared" ;;
	-h|--help) usage ;;
	*) usage; exit 1 ;;
esac
