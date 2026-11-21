#!/system/bin/sh
# fb unisoc - Unisoc/Spreadtrum tools: spd_dump, spd_dump_tk, pacextractor, bkerler
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

usage() {
	cat <<EOF
fb unisoc <command>

  flash <args>                spd_dump flash (pass-through)
  readback <args>             spd_dump readback
  pac list <file.pac>         list partitions in a PAC firmware
  pac extract <file.pac> [-p boot,system] [dir]
  sfd <args>                  spd_dump_tk pass-through (TomKing062 fork, the CLI behind sfd_tool)
  bk <args>                   bkerler/unisoc python pass-through

the device must be in download mode (powered off, hold vol-down, plug USB;
fb usb shows 1782:4d00 for Unisoc download mode)
EOF
}

SPD=$(command -v spd_dump || command -v fb-spd_dump) || SPD=""
SFD=$(command -v spd_dump_tk || command -v fb-spd_dump_tk) || SFD=""
PAC=$(command -v pacextractor || command -v fb-pacextractor) || PAC=""
BK_PY="$FB_MOD/python/bkerler-unisoc"

need_root
cmd=$1
[ -n "$cmd" ] && shift
case $cmd in
flash)
	[ -n "$SPD" ] || die "spd_dump not in this build"
	$SPD "$@"
	;;
readback)
	[ -n "$SPD" ] || die "spd_dump not in this build"
	$SPD "$@"
	;;
pac)
	[ -n "$PAC" ] || die "pacextractor not in this build"
	$PAC "$@"
	;;
sfd)
	[ -n "$SFD" ] || die "spd_dump_tk not in this build"
	$SFD "$@"
	;;
bk)
	# TODO: no component for bkerler/unisoc yet, so this always falls through
	# for now. leaving it so the command exists once i add the recipe.
	[ -d "$BK_PY" ] || die "bkerler/unisoc not in this build"
	command -v python3 >/dev/null 2>&1 || die "python3 is needed (install via Termux)"
	PYTHONPATH="$BK_PY" python3 -m unisoc "$@"
	;;
''|-h|--help) usage ;;
*) usage; exit 1 ;;
esac
