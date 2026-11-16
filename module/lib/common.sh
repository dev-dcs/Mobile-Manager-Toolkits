# shared by the fb-*.sh scripts - @Dev_DcS
# shellcheck shell=sh

FB_LIB=${FB_LIB:-$(cd "${0%/*}/../lib" 2>/dev/null && pwd)}
FB_MOD=${FB_MOD:-${FB_LIB%/lib}}
FB_DATA=${FB_DATA:-/data/local/tmp/flashbench}
FB_CONF=${FB_CONF:-$FB_DATA/fb.conf}
FB_OUT=${FB_OUT:-$FB_DATA/out}

SERIAL=${ANDROID_SERIAL:-}

msg()  { printf '%s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }
die()  { printf 'x %s\n' "$*" >&2; exit 1; }

conf() {
	sed -n "s/^$1=//p" "$FB_CONF" 2>/dev/null | tail -n 1
}

conf_set() {
	if grep -q "^$1=" "$FB_CONF" 2>/dev/null; then
		sed -i "s|^$1=.*|$1=$2|" "$FB_CONF"
	else
		echo "$1=$2" >> "$FB_CONF"
	fi
}

need_root() {
	[ "$(id -u)" = 0 ] || die "run this as root (su)"
}

now()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
stamp() { date -u +%Y%m%d-%H%M%S; }

# -s serial is handled here so every script gets it for free
take_serial() {
	case $1 in
		-s) SERIAL=$2; return 0 ;;
		-s*) SERIAL=${1#-s}; return 0 ;;
	esac
	return 1
}

A() {
	if [ -n "$SERIAL" ]; then adb -s "$SERIAL" "$@"; else adb "$@"; fi
}

# shell on the target, raw (no pty), keeps the remote exit code
ash() { A shell -T "$*" < /dev/null; }

# same with su on the target (only for rooted targets)
asu() { A shell -T "su -c '$*'" < /dev/null; }

target_has_su() {
	[ "$(A shell -T 'su -c id -u' 2>/dev/null | tr -d '\r')" = 0 ]
}

adb_devices() {
	A start-server >/dev/null 2>&1
	adb devices | awk 'NR > 1 && NF >= 2 { print $1, $2 }'
}

# picks the only adb device or the one given with -s, dies otherwise
pick_device() {
	_devs=$(adb_devices)
	if [ -n "$SERIAL" ]; then
		_st=$(echo "$_devs" | awk -v s="$SERIAL" '$1 == s { print $2 }')
		[ -n "$_st" ] || die "$SERIAL is not connected over adb"
	else
		_n=$(echo "$_devs" | grep -c .)
		[ "$_n" -gt 0 ] || die "no adb device, try: fb usb"
		[ "$_n" -eq 1 ] || { echo "$_devs" >&2; die "more than one device, use -s <serial>"; }
		SERIAL=${_devs%% *}
		_st=${_devs#* }
	fi
	case $_st in
		device|recovery) ;;
		unauthorized) die "$SERIAL: accept the USB debugging prompt on the target" ;;
		*) die "$SERIAL is in state '$_st'" ;;
	esac
	export SERIAL
}

prop() { ash getprop "$1" | tr -d '\r'; }

# fetch <url> - body on stdout. Our curl first (verifies TLS, uses DoH because
# a static musl binary cannot use Android's resolver), then root manager busybox.
fb_fetch() {
	_t=${TMPDIR:-/data/local/tmp}/fb.fetch.$$
	_doh=$(conf doh_url)
	if command -v curl >/dev/null 2>&1; then
		if [ -f /etc/resolv.conf ] || [ -z "$_doh" ]; then
			curl -fsSL -m 30 -o "$_t" "$@" 2>/dev/null && { cat "$_t"; rm -f "$_t"; return 0; }
		else
			curl -fsSL -m 30 --doh-url "$_doh" -o "$_t" "$@" 2>/dev/null && { cat "$_t"; rm -f "$_t"; return 0; }
		fi
	fi
	for _bb in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
		[ -x "$_bb" ] || continue
		"$_bb" wget -q -T 30 -O "$_t" "$1" 2>/dev/null && { cat "$_t"; rm -f "$_t"; return 0; }
	done
	rm -f "$_t"
	return 1
}

# notify <title> <text> - Android notification and/or ntfy, per fb.conf
notify() {
	_how=$(conf notify)
	case $_how in none) return 0 ;; esac
	# quotes would break the command line below
	_nt=$(printf %s "$1" | tr -d "'") _nb=$(printf %s "$2" | tr -d "'")
	_doh=$(conf doh_url)
	[ -f /etc/resolv.conf ] && _doh=

	case $_how in android|both|'')
		_cmd="cmd notification post -S bigtext -t '$_nt' flashbench '$_nb'"
		su 2000 -c "$_cmd" >/dev/null 2>&1 ||
			su -lp 2000 -c "$_cmd" >/dev/null 2>&1 ||
			eval "$_cmd" >/dev/null 2>&1 ||
			warn "could not post the Android notification"
		;;
	esac

	case $_how in ntfy|both)
		_url=$(conf ntfy_url)
		[ -n "$_url" ] || return 0
		if command -v curl >/dev/null 2>&1; then
			curl -fsS -m 30 ${_doh:+--doh-url "$_doh"} -H "Title: $_nt" -d "$_nb" "$_url" >/dev/null 2>&1
		else
			for _bb in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
				[ -x "$_bb" ] && "$_bb" wget -q -O /dev/null --header "Title: $_nt" --post-data "$_nb" "$_url" && break
			done
		fi
		;;
	esac
	return 0
}

# root managers show module.prop's description, use it as a status line
set_status() {
	_p=$FB_MOD/module.prop
	[ -w "$_p" ] || return 0
	_base=$(sed -n 's/^description=//p' "$_p" | sed 's/^\[[^]]*\] //')
	if [ -n "$1" ]; then
		sed -i "s|^description=.*|description=[$1] $_base|" "$_p"
	else
		sed -i "s|^description=.*|description=$_base|" "$_p"
	fi
}

# confirm <question> - only a typed "yes" goes through (FB_YES=1 skips)
confirm() {
	[ "${FB_YES:-0}" = 1 ] && return 0
	printf '%s\ntype yes to go on: ' "$1" >&2
	if [ -r /dev/tty ] && { read -r _a < /dev/tty; } 2>/dev/null; then :; else read -r _a; fi
	[ "$_a" = yes ]
}

# partition folder and "name size" table of a rooted target
target_byname() {
	asu 'for d in /dev/block/by-name /dev/block/bootdevice/by-name; do [ -d $d ] && { echo $d; break; }; done' | tr -d '\r'
}

target_parts() {
	asu "cd $1 && for p in *; do echo \$p \$(blockdev --getsize64 \$p); done" | tr -d '\r'
}
