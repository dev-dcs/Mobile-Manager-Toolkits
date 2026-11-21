#!/system/bin/sh
# fb payload - inspect, extract and rebuild A/B update_engine payload.bin
# dump = payload-dumper-go (native), info/repack = vendored fb_payload.py
# @Dev_DcS

. "${0%/*}/../lib/common.sh"
. "$FB_LIB/py.sh"

PY=$FB_MOD/share/py/fb_payload.py
pd=$(command -v payload-dumper-go || command -v fb-payload-dumper-go || true)

usage() {
	cat <<EOF
fb payload <command>

  info <payload.bin|ota.zip>              partitions, block size, ops
  dump <payload.bin|ota.zip> [-p a,b] [-o dir]
                                          extract partitions (payload-dumper-go)
  repack -o out.bin <name:img> ...        build a full payload from images
  repack -o out.bin --from-dir <dir>      ... from <dir>/<name>.img
      --xz            xz-compress the data (smaller, slower)
      --block-size N  default 4096

repack makes an unsigned FULL payload (REPLACE ops). Flash with update_engine
where unsigned is allowed, or sign the metadata yourself.
EOF
}

# payload.bin out of an OTA zip if needed; echoes a path, may be temp
resolve_payload() {
	case $1 in
	*.zip)
		t=${TMPDIR:-/data/local/tmp}/fb-payload.$$
		mkdir -p "$t"
		unzip -o -q "$1" payload.bin -d "$t" 2>/dev/null || die "no payload.bin in $1"
		echo "$t/payload.bin"
		;;
	*) echo "$1" ;;
	esac
}

cmd=$1
[ -n "$cmd" ] && shift
case $cmd in
info)
	[ -f "$1" ] || { usage; exit 1; }
	pyrun "$PY" info "$(resolve_payload "$1")"
	;;
dump)
	[ -n "$pd" ] || die "payload-dumper-go not in this build"
	[ -f "$1" ] || { usage; exit 1; }
	f=$1; shift
	out=$FB_OUT/payload/$(basename "${f%.*}")
	parts=""
	while [ $# -gt 0 ]; do
		case $1 in -p) parts=$2; shift ;; -o) out=$2; shift ;; *) die "bad option $1" ;; esac
		shift
	done
	mkdir -p "$out"
	if [ -n "$parts" ]; then "$pd" -o "$out" -p "$parts" "$f"; else "$pd" -o "$out" "$f"; fi
	msg "$out"
	;;
repack)
	[ -f "$PY" ] || die "fb_payload.py missing"
	pyrun "$PY" repack "$@"
	;;
''|-h|--help) usage ;;
*) usage; exit 1 ;;
esac
