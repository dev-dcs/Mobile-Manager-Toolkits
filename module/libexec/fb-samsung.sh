#!/system/bin/sh
# fb samsung - Samsung firmware tools: unpack, flash via odin4/heimdall,
# download via samloader, PIT management, Exynos USB exploit
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

ODIN=$(command -v odin4 || command -v fb-odin4 || true)
HEIMDALL=$(command -v heimdall || command -v fb-heimdall || true)
SAMLOADER=$(command -v samloader || command -v fb-samloader || true)

usage() {
	cat <<EOF
fb samsung <command>

  unpack <AP|BL|CP|CSC.tar.md5> [dir]   check the md5 trailer, untar, un-lz4
  pit [file.pit]                        download PIT (device in download mode)
  plan <dir> <file.pit>                 map images to partitions and show the command
  flash <args>                          flash via odin4 (Thor protocol) or heimdall
  download <model> <csc> [dir]          download firmware via samloader-rs
  check-update <model> <csc>            check for firmware updates
  detect                                detect Samsung device in download mode

tools in PATH: ${ODIN:+odin4 }${HEIMDALL:+heimdall }${SAMLOADER:+samloader}
EOF
}

unpack() {
	f=$1
	[ -f "$f" ] || die "no such file: $f"
	out=${2:-${f%.tar*}}
	mkdir -p "$out"

	case $f in *.md5)
		# Odin appends "<md5>  <name>" after the tar, md5 covers everything before it
		trailer=$(tail -c 200 "$f" | tr -d '\0' | tail -n 1)
		want=${trailer%% *}
		tsize=$(printf '%s\n' "$trailer" | wc -c)
		total=$(wc -c < "$f")
		got=$(head -c $((total - tsize)) "$f" | md5sum | cut -d' ' -f1)
		if [ "$got" = "$want" ]; then msg "md5 ok"; else die "md5 mismatch: file says $want, data is $got"; fi
		;;
	esac

	tar -xf "$f" -C "$out" || die "tar failed"
	for z in "$out"/*.lz4; do
		[ -f "$z" ] || continue
		printf '  %s\n' "${z##*/}"
		lz4 -dq "$z" "${z%.lz4}" && rm -f "$z"
	done
	msg "unpacked to $out"
	ls -l "$out"
}

pit() {
	f=${1:-$FB_OUT/samsung/device-$(stamp).pit}
	mkdir -p "${f%/*}"
	heimdall download-pit --output "$f" --no-reboot || die "heimdall could not read the pit"
	msg "$f"
	msg "the device stays in download mode, next session needs: heimdall ... --resume"
}

plan() {
	dir=$1 pitf=$2
	[ -d "$dir" ] && [ -f "$pitf" ] || die "fb samsung plan <dir> <file.pit>"
	map=$(heimdall print-pit --file "$pitf" --no-reboot 2>/dev/null | awk '
		/^Partition Name:/ { sub(/^Partition Name: */, ""); name = $0 }
		/^Flash Filename:/ { sub(/^Flash Filename: */, ""); if ($0 != "" && $0 != "-") print $0 "|" name }')
	[ -n "$map" ] || die "could not parse the pit"

	args="" miss=""
	for img in "$dir"/*; do
		[ -f "$img" ] || continue
		b=${img##*/}
		case $b in *.md5|*.pit|meta-data|*.txt) continue ;; esac
		part=$(echo "$map" | awk -F'|' -v f="$b" '$1 == f { print $2; exit }')
		if [ -n "$part" ]; then
			args="$args --$part $img"
			printf '  %-28s -> %s\n' "$b" "$part"
		else
			miss="$miss $b"
		fi
	done
	[ -n "$miss" ] && warn "not in the pit, skipped:$miss"
	[ -n "$args" ] || die "nothing matched"
	echo
	echo "heimdall flash$args"
	echo
	msg "check it before running. Add --resume if the pit was read in the same session."
}

flash_samsung() {
	if [ -n "$ODIN" ]; then
		msg "flashing via odin4 (Thor protocol)"
		$ODIN "$@"
	elif [ -n "$HEIMDALL" ]; then
		msg "flashing via heimdall"
		$HEIMDALL flash "$@"
	else
		die "neither odin4 nor heimdall in this build"
	fi
}

download_fw() {
	[ -n "$SAMLOADER" ] || die "samloader not in this build"
	model=$1 csc=$2 dir=${3:-$FB_OUT/samsung/fw}
	[ -n "$model" ] && [ -n "$csc" ] || die "fb samsung download <model> <csc> [dir]"
	mkdir -p "$dir"
	$SAMLOADER download -m "$model" -c "$csc" -o "$dir"
	msg "firmware saved to $dir"
}

check_update() {
	[ -n "$SAMLOADER" ] || die "samloader not in this build"
	[ -n "$1" ] && [ -n "$2" ] || die "fb samsung check-update <model> <csc>"
	$SAMLOADER check-update -m "$1" -c "$2"
}

detect_samsung() {
	if [ -n "$ODIN" ]; then
		$ODIN --detect 2>/dev/null && return 0
	fi
	if [ -n "$HEIMDALL" ]; then
		$HEIMDALL detect 2>/dev/null && return 0
	fi
	die "no Samsung device in download mode detected"
}

cmd=$1
[ -n "$cmd" ] && shift
case $cmd in
	unpack) unpack "$@" ;;
	pit) need_root; pit "$@" ;;
	plan) plan "$@" ;;
	flash) need_root; flash_samsung "$@" ;;
	download) download_fw "$@" ;;
	check-update) check_update "$@" ;;
	detect) need_root; detect_samsung ;;
	''|-h|--help) usage ;;
	*) usage; exit 1 ;;
esac
