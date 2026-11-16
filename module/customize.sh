# FlashBench installer - @Dev_DcS
# sourced by Magisk / KernelSU / APatch

SKIPUNZIP=0
DATA=/data/local/tmp/flashbench

[ "$ARCH" = arm64 ] || abort "! arm64 only, this device reports $ARCH"
[ "$API" -ge 35 ] || abort "! needs Android 15 or newer (API $API)"
[ "$API" -gt 37 ] && ui_print "! API $API is newer than what was tested (35-37)"

if [ "$KSU" = true ]; then
	ui_print "- KernelSU $KSU_VER ($KSU_VER_CODE)"
elif [ "$APATCH" = true ]; then
	ui_print "- APatch $APATCH_VER_CODE"
else
	ui_print "- Magisk $MAGISK_VER ($MAGISK_VER_CODE)"
fi

# binaries are linked for 16K pages, which also covers 4K kernels.
# Check against the page size this kernel actually runs with.
. "$MODPATH/lib/elf.sh"
ps=$(getconf PAGESIZE 2>/dev/null)
[ -n "$ps" ] || ps=4096
bad=""
for f in "$MODPATH"/system/bin/* "$MODPATH"/system/bin/.[a-z]*; do
	[ -f "$f" ] || continue
	elf_maps "$f" "$ps"
	[ $? = 1 ] && bad="$bad ${f##*/}"
done
[ -z "$bad" ] || abort "! these cannot be mapped with $ps byte pages:$bad"
ui_print "- page size $ps, all binaries map (built for 4K and 16K)"

# ---------------------------------------------------------------------------
# conflict check: do any of our command names already exist on the device?
# if so, ask what to do with a vol-key menu (20s, defaults to coexist).
# ---------------------------------------------------------------------------

# read one volume key press. echoes PLUS / MINUS / TIMEOUT. $1 = seconds.
# only the press (value DOWN) counts, release is ignored. getevent may not be
# usable under KSU/APatch app installs, hence the timeout + graceful fallback.
read_vol() {
	local out
	out=$(timeout "$1" sh -c '
		getevent -l 2>/dev/null | while read -r _d _t code val; do
			[ "$val" = DOWN ] || continue
			case $code in
				KEY_VOLUMEUP)   echo PLUS;  break ;;
				KEY_VOLUMEDOWN) echo MINUS; break ;;
			esac
		done
	' 2>/dev/null)
	echo "${out:-TIMEOUT}"
}

draw_menu() {
	local s=$1 m1="  1) cancel" m2="  2) continue anyway (risky)" m3="  3) keep system's, install ours as fb-*"
	eval "m$s=\"> \${m$s#  }\""
	ui_print "$m1"
	ui_print "$m2"
	ui_print "$m3"
}

# returns the chosen option (1/2/3) as its exit code
conflict_menu() {
	local sel=3 endt now k
	draw_menu $sel
	# no input device? don't hang the install, take the default
	[ -c /dev/input/event0 ] || command -v getevent >/dev/null 2>&1 || return $sel
	endt=$(( $(date +%s) + 20 ))
	while :; do
		now=$(date +%s)
		[ "$now" -ge "$endt" ] && { ui_print "  (no input, going with $sel)"; return $sel; }
		k=$(read_vol $(( endt - now )))
		case $k in
			MINUS)   sel=$(( sel % 3 + 1 )); ui_print "  -> $sel"; draw_menu $sel ;;
			PLUS)    ui_print "  == chose $sel"; return $sel ;;
			TIMEOUT) ui_print "  (timed out, going with $sel)"; return $sel ;;
		esac
	done
}

# a name is "taken" if it already sits in any real PATH dir. skip names our own
# previous install owns (upgrade) - those would show up as conflicts otherwise.
PATHDIRS="/system/bin /system/xbin /vendor/bin /odm/bin /product/bin /system_ext/bin"
old=/data/adb/modules/$MODID
conflicts=""
for f in "$MODPATH"/system/bin/*; do
	n=${f##*/}
	[ "$n" = fb ] && continue
	[ -e "$old/system/bin/$n" ] && continue
	for d in $PATHDIRS; do
		[ -e "$d/$n" ] && { conflicts="$conflicts $n"; break; }
	done
done

choice=3
if [ -n "$conflicts" ]; then
	ui_print " "
	ui_print "**********************************************"
	ui_print "  some command names are already on this phone:"
	ui_print "   $conflicts"
	ui_print " "
	ui_print "  what should i do?  (Vol- move, Vol+ pick)"
	ui_print "**********************************************"
	conflict_menu
	choice=$?
fi

case $choice in
1)
	abort "- cancelled, nothing installed"
	;;
2)
	ui_print "- option 2: ours will shadow the system commands (risky)"
	# leave them under their real names; the module mount wins over /system
	;;
*)
	[ -n "$conflicts" ] && ui_print "- option 3: system keeps its commands, ours go in as fb-*"
	for n in $conflicts; do
		[ -f "$MODPATH/system/bin/$n" ] &&
			mv "$MODPATH/system/bin/$n" "$MODPATH/system/bin/fb-$n"
	done
	;;
esac

# something earlier in PATH wins over /system/bin, just say so
for f in "$MODPATH"/system/bin/*; do
	n=${f##*/}
	for d in /product/bin /apex/com.android.runtime/bin /apex/com.android.art/bin /system_ext/bin; do
		[ -x "$d/$n" ] && ui_print "  note: $d/$n comes first in PATH"
	done
done

# ---------------------------------------------------------------------------

mkdir -p "$DATA/home"
if [ -f "$DATA/fb.conf" ]; then
	# keep user values, add keys that are new in this version
	while IFS= read -r line; do
		case $line in '#'*|'') continue ;; esac
		grep -q "^${line%%=*}=" "$DATA/fb.conf" || echo "$line" >> "$DATA/fb.conf"
	done < "$MODPATH/fb.conf.default"
else
	cp "$MODPATH/fb.conf.default" "$DATA/fb.conf"
fi
chmod 700 "$DATA"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/bin" 0 2000 0755 0755
set_perm_recursive "$MODPATH/libexec" 0 0 0755 0755
for f in service.sh action.sh uninstall.sh; do
	[ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done

n=0
for f in "$MODPATH"/system/bin/*; do n=$((n + 1)); done
ui_print "- $n tools in /system/bin, run 'fb' from a root shell"
ui_print "- storage at $DATA"
grep -q '^watch=1' "$DATA/fb.conf" && ui_print "- upstream watcher on (fb watch --status)"
