#!/system/bin/sh
# fb ota - payload.bin helpers around payload-dumper-go
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

usage() {
	cat <<EOF
fb ota <command>

  list <ota.zip|payload.bin>                     partitions inside
  extract <ota.zip|payload.bin> [-p a,b] [-o dir] pull images out (all if no -p)
EOF
}

pd=$(command -v payload-dumper-go || command -v fb-payload-dumper-go) || die "payload-dumper-go is not in this build"

cmd=$1
[ -n "$cmd" ] && shift
case $cmd in
	list)
		[ -f "$1" ] || die "no such file: $1"
		"$pd" -l "$1"
		;;
	extract)
		f=$1; shift
		[ -f "$f" ] || die "no such file: $f"
		out=$FB_OUT/ota/$(basename "${f%.*}")
		parts=""
		while [ $# -gt 0 ]; do
			case $1 in
				-p) parts=$2; shift ;;
				-o) out=$2; shift ;;
				*) die "unknown option $1" ;;
			esac
			shift
		done
		mkdir -p "$out"
		if [ -n "$parts" ]; then "$pd" -o "$out" -p "$parts" "$f"; else "$pd" -o "$out" "$f"; fi
		msg "$out"
		;;
	''|-h|--help) usage ;;
	*) usage; exit 1 ;;
esac
