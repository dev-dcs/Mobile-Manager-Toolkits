#!/system/bin/sh
# fb oppo - Oppo/Realme/OnePlus firmware tools (ofp/ops decrypt)
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

usage() {
	cat <<EOF
fb oppo <command>

  decrypt <file.ofp|file.ops> [outdir]   decrypt OFP/OPS firmware
  list <file.ofp|file.ops>               list partitions inside

needs python3 on the device (install via Termux)
EOF
}

PY="$FB_MOD/python/oppo_decrypt"

need_root
cmd=$1
[ -n "$cmd" ] && shift
case $cmd in
decrypt|list)
	[ -d "$PY" ] || die "oppo_decrypt not in this build"
	command -v python3 >/dev/null 2>&1 || die "python3 needed (install via Termux)"
	[ -f "$1" ] || die "fb oppo $cmd <file>"
	if [ "$cmd" = decrypt ]; then
		out=${2:-$(dirname "$1")/$(basename "${1%.*}")-decrypted}
		mkdir -p "$out"
		PYTHONPATH="$PY" python3 "$PY/ofp_mtk_decrypt.py" "$1" "$out" 2>/dev/null ||
		PYTHONPATH="$PY" python3 "$PY/ofp_qc_decrypt.py" "$1" "$out" 2>/dev/null ||
		PYTHONPATH="$PY" python3 "$PY/ops_decrypt.py" "$1" "$out" 2>/dev/null ||
		die "decryption failed (not an OFP/OPS, or unknown key)"
		msg "$out"
	else
		PYTHONPATH="$PY" python3 "$PY/ofp_mtk_decrypt.py" --list "$1" 2>/dev/null ||
		PYTHONPATH="$PY" python3 "$PY/ofp_qc_decrypt.py" --list "$1" 2>/dev/null ||
		PYTHONPATH="$PY" python3 "$PY/ops_decrypt.py" --list "$1" 2>/dev/null ||
		die "could not parse the file"
	fi
	;;
''|-h|--help) usage ;;
*) usage; exit 1 ;;
esac
