#!/system/bin/sh
# fb mtk - MediaTek BROM/DA flash and unlock via penumbra/antumbra (native)
# and mtkclient (python) for legacy V3 devices. @Dev_DcS

. "${0%/*}/../lib/common.sh"

usage() {
	cat <<EOF
fb mtk <command>

native (antumbra — V5/V6 XFlash/XML devices):
  flash <scatter.txt|partition> <file>   flash a partition
  readback <partition> <file>            read back a partition image
  erase <partition>                      erase a partition
  unlock                                 bootloader unlock (vulnerable devices)
  relock                                 bootloader relock
  rpmb read|write|erase                  RPMB operations (eMMC only)
  mem read|write <addr> <len|file>       arbitrary memory read/write
  info                                   device info over BROM/DA

python (mtkclient — V3/Legacy + wider SoC support):
  mtk <args>                             pass-through to mtkclient (needs python)

the device must be in BROM or preloader mode (powered off, hold vol-down,
plug USB; or fb usb will tell you the mode)
EOF
}

AT=$(command -v antumbra || command -v fb-antumbra) || AT=""
MTK_PY="$FB_MOD/python/mtkclient"

has_antumbra() { [ -n "$AT" ]; }
has_mtkclient() { [ -d "$MTK_PY" ] && command -v python3 >/dev/null 2>&1; }

run_mtk() {
	[ -d "$MTK_PY" ] || die "mtkclient is not in this build"
	command -v python3 >/dev/null 2>&1 || die "python3 is needed for mtkclient (install via Termux)"
	PYTHONPATH="$MTK_PY" python3 -m mtkclient.mtk_gui "$@" 2>/dev/null ||
	PYTHONPATH="$MTK_PY" python3 "$MTK_PY/mtk" "$@"
}

need_root
cmd=$1
[ -n "$cmd" ] && shift
case $cmd in
flash)
	has_antumbra || die "antumbra not in this build; fb mtk mtk write <part> <file>"
	[ -n "$2" ] || die "fb mtk flash <partition|scatter> <file>"
	$AT flash "$@"
	;;
readback)
	has_antumbra || die "antumbra not in this build; fb mtk mtk rl <part> <file>"
	[ -n "$2" ] || die "fb mtk readback <partition> <file>"
	$AT readback "$@"
	;;
erase)
	[ -n "$1" ] || die "fb mtk erase <partition>"
	confirm "erase partition $1?" || die "stopped"
	has_antumbra && { $AT erase "$@"; exit; }
	has_mtkclient && { run_mtk e "$@"; exit; }
	die "neither antumbra nor mtkclient available"
	;;
unlock)
	warn "bootloader unlock is permanent on most devices and may void warranty"
	confirm "unlock the bootloader?" || die "stopped"
	has_antumbra && { $AT unlock; exit; }
	has_mtkclient && { run_mtk da seccfg unlock; exit; }
	die "neither antumbra nor mtkclient available"
	;;
relock)
	confirm "relock the bootloader?" || die "stopped"
	has_antumbra && { $AT relock; exit; }
	has_mtkclient && { run_mtk da seccfg lock; exit; }
	die "neither antumbra nor mtkclient available"
	;;
rpmb)
	has_antumbra || die "RPMB needs antumbra"
	$AT rpmb "$@"
	;;
mem)
	has_antumbra || die "memory r/w needs antumbra"
	$AT mem "$@"
	;;
info)
	has_antumbra && { $AT info; exit; }
	has_mtkclient && { run_mtk printgpt; exit; }
	die "neither antumbra nor mtkclient available"
	;;
mtk)
	run_mtk "$@"
	;;
''|-h|--help) usage ;;
*) usage; exit 1 ;;
esac
