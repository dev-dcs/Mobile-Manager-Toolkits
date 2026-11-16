#!/system/bin/sh
# FlashBench - @Dev_DcS
MODDIR=${0%/*}
FB_CONF=/data/local/tmp/flashbench/fb.conf

# the log catcher, if the user asked for it to come up on boot
if [ -f "$MODDIR/libexec/fb-log.sh" ] && grep -q '^log_boot=1' "$FB_CONF" 2>/dev/null; then
	(
		until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 10; done
		sh "$MODDIR/libexec/fb-log.sh" start
	) </dev/null >/dev/null 2>&1 &
fi

# the upstream watcher daemon, only when turned on
[ -f "$MODDIR/libexec/fb-watch.sh" ] || exit 0
grep -q '^watch=1' "$FB_CONF" 2>/dev/null || exit 0

(
	until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 10; done
	sleep 90
	exec sh "$MODDIR/libexec/fb-watch.sh" --daemon
) </dev/null >/dev/null 2>&1 &
