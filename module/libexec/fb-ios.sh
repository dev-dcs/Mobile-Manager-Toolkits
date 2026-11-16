#!/system/bin/sh
# fb ios - Apple iOS device management over USB OTG
# wraps irecovery, libimobiledevice tools, img4tool, gaster, palera1n, futurerestore
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

usage() {
	cat <<EOF
fb ios <command>

device info & management (libimobiledevice / idevice-tools):
  info                    device info (UDID, model, iOS version, serial)
  list                    list connected iOS devices
  pair                    pair with the connected device
  syslog                  stream the device syslog
  screenshot [file]       take a screenshot
  backup <dir>            full device backup
  restore <dir>           restore from a backup
  install <ipa>           install an IPA
  apps                    list installed apps
  diag restart|shutdown   reboot or shut down the device
  crashreport <dir>       pull crash reports

recovery & DFU:
  recovery enter          enter recovery mode
  recovery exit           exit recovery mode (boot normally)
  recovery info           device info in recovery/DFU mode
  recovery shell          interactive irecovery shell
  recovery send <file>    send a file (iBSS, iBEC, ramdisk, etc.)
  recovery cmd <string>   send a command string

image tools:
  img4 info <file>        parse IMG4/IM4P/IM4M
  img4 extract <file> [payload] [im4p]
  img4 create -t <tag> -p <payload> [-m <im4m>] -o <out>
  img3 info <file>        parse IMG3

checkm8 / jailbreak:
  gaster <args>           checkm8 exploit (A5-A11), pass-through
  palera1n <args>         palera1n jailbreak, pass-through

restore:
  futurerestore <args>    restore with custom APTickets, pass-through

run any subcommand with -h for its own help
EOF
}

# resolve the right tool: native (libimobiledevice) or Rust (idevice-tools)
find_tool() {
	for t in "$1" "fb-$1"; do
		command -v "$t" >/dev/null 2>&1 && { echo "$t"; return 0; }
	done
	return 1
}

need_root
cmd=$1
[ -n "$cmd" ] && shift
case $cmd in
# --- libimobiledevice / idevice-tools ------
info)
	t=$(find_tool ideviceinfo) || die "ideviceinfo not in this build"
	$t "$@"
	;;
list)
	t=$(find_tool idevice_id) || t=$(find_tool ideviceinfo)
	[ -n "$t" ] || die "no idevice tool in this build"
	$t -l 2>/dev/null || $t "$@"
	;;
pair)
	t=$(find_tool idevicepair) || die "idevicepair not in this build"
	$t pair "$@"
	;;
syslog)
	t=$(find_tool idevicesyslog) || die "idevicesyslog not in this build"
	$t "$@"
	;;
screenshot)
	t=$(find_tool idevicescreenshot) || die "idevicescreenshot not in this build"
	f=${1:-$FB_OUT/ios/screenshot-$(stamp).png}
	mkdir -p "$(dirname "$f")"
	$t "$f" && msg "$f"
	;;
backup)
	[ -n "$1" ] || die "fb ios backup <dir>"
	t=$(find_tool idevicebackup2) || die "idevicebackup2 not in this build"
	mkdir -p "$1"
	$t backup --full "$1"
	;;
restore)
	[ -d "$1" ] || die "fb ios restore <backup-dir>"
	t=$(find_tool idevicebackup2) || die "idevicebackup2 not in this build"
	confirm "restore from $1?" || die "stopped"
	$t restore "$1"
	;;
install)
	[ -f "$1" ] || die "fb ios install <file.ipa>"
	t=$(find_tool ideviceinstaller) || die "ideviceinstaller not in this build"
	$t -i "$1"
	;;
apps)
	t=$(find_tool ideviceinstaller) || die "ideviceinstaller not in this build"
	$t -l "$@"
	;;
diag)
	t=$(find_tool idevicediagnostics) || die "idevicediagnostics not in this build"
	case $1 in
		restart|shutdown|sleep) $t "$1" ;;
		*) die "fb ios diag restart|shutdown|sleep" ;;
	esac
	;;
crashreport)
	[ -n "$1" ] || die "fb ios crashreport <dir>"
	t=$(find_tool idevicecrashreport) || die "idevicecrashreport not in this build"
	mkdir -p "$1"
	$t "$1"
	;;

# --- recovery / DFU ------
recovery)
	sub=$1; shift
	t=$(find_tool irecovery) || die "irecovery not in this build"
	case $sub in
		enter) $t -e ;;
		exit)  $t -n ;;
		info)  $t -q ;;
		shell) $t -s ;;
		send)  [ -f "$1" ] || die "fb ios recovery send <file>"; $t -f "$1" ;;
		cmd)   [ -n "$1" ] || die "fb ios recovery cmd <string>"; $t -c "$*" ;;
		''|-h) echo "fb ios recovery enter|exit|info|shell|send|cmd" ;;
		*) die "unknown recovery command: $sub" ;;
	esac
	;;

# --- img4/img3 ------
img4)
	t=$(find_tool img4tool) || die "img4tool not in this build"
	sub=$1; shift
	case $sub in
		info)    $t -a "$@" ;;
		extract) $t -e "$@" ;;
		create)  $t -c "$@" ;;
		*) $t "$sub" "$@" ;;
	esac
	;;
img3)
	t=$(find_tool img3tool) || die "img3tool not in this build"
	$t "$@"
	;;

# --- checkm8 / jailbreak ------
gaster)
	t=$(find_tool gaster) || die "gaster not in this build"
	$t "$@"
	;;
palera1n)
	t=$(find_tool palera1n) || die "palera1n not in this build"
	$t "$@"
	;;

# --- futurerestore ------
futurerestore)
	t=$(find_tool futurerestore) || die "futurerestore not in this build"
	$t "$@"
	;;

''|-h|--help) usage ;;
*) usage; exit 1 ;;
esac
