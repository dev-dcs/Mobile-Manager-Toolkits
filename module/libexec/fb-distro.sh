#!/system/bin/sh
# fb distro - Ubuntu 24.04 arm64 in a chroot, with the full dev toolset from
# share/distro/packages.list. The static tools cover the shell; this covers
# compilers, JDKs, packaging and everything else that can't be a single binary.
# @Dev_DcS

. "${0%/*}/../lib/common.sh"

DDIR=$FB_DATA/distro
ROOT=$DDIR/ubuntu-24.04
LIST=$FB_MOD/share/distro/packages.list
EXTRA=$DDIR/extra.list
BASE_URL=https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release
MIRROR=http://ports.ubuntu.com/ubuntu-ports
DNS=${FB_DNS:-1.1.1.1 8.8.8.8}

usage() {
	cat <<EOF
fb distro <command>

  install [--base]   download Ubuntu 24.04 (arm64), set it up and install the
                     package list. --base stops after the bare system
  enter              root shell inside (also the default with no command)
  run <cmd...>       run one command inside
  apt <args>         apt-get inside, e.g. fb distro apt install neofetch
  sync               install whatever from the list is still missing
  status             where it lives, size, what is mounted
  umount             unmount everything fb distro mounted
  remove             delete the whole rootfs (asks first)

rootfs:   $ROOT
your own extra packages, one per line: $EXTRA
internal storage shows up inside as /sdcard
EOF
}

# mounts have to be visible from every root shell, so work in init's namespace
if [ "$(id -u)" = 0 ] && [ -z "$FB_DISTRO_NS" ] &&
	[ "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)" ] &&
	nsenter -t 1 -m true 2>/dev/null; then
	FB_DISTRO_NS=1 exec nsenter -t 1 -m sh "$0" "$@"
fi

installed() { [ -f "$ROOT/etc/os-release" ]; }

mounted() { grep -q " $1 " /proc/mounts; }

tar_bin() {
	for t in busybox fb-busybox; do
		command -v "$t" >/dev/null 2>&1 && { echo "$t tar"; return; }
	done
	echo tar
}

free_mb() { df -k "$1" 2>/dev/null | awk 'NR == 2 { print int($4 / 1024) }'; }

# get <url> <file> - big download, resumes a broken one. fb_fetch caps at 30s
get() {
	_doh=$(conf doh_url)
	[ -f /etc/resolv.conf ] && _doh=
	if command -v curl >/dev/null 2>&1; then
		curl -fL --retry 3 -C - ${_doh:+--doh-url "$_doh"} -o "$2" "$1" && return 0
	fi
	for _bb in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
		[ -x "$_bb" ] && "$_bb" wget -c -O "$2" "$1" && return 0
	done
	return 1
}

mount_all() {
	installed || die "not installed, run: fb distro install"
	if ! mounted "$ROOT"; then
		# /data is nosuid,nodev for apps; a bind of the rootfs onto itself can
		# carry its own flags without touching /data
		mount -o bind "$ROOT" "$ROOT" || die "cannot bind $ROOT"
		mount -o remount,bind,exec,suid,dev "$ROOT" 2>/dev/null || warn "could not lift nosuid/nodev, some packages may complain"
	fi
	mounted "$ROOT/dev" || mount -o bind /dev "$ROOT/dev"
	mounted "$ROOT/dev/pts" || mount -o bind /dev/pts "$ROOT/dev/pts"
	mkdir -p "$ROOT/dev/shm"
	mounted "$ROOT/dev/shm" || mount -t tmpfs -o mode=1777 tmpfs "$ROOT/dev/shm"
	mounted "$ROOT/proc" || mount -t proc proc "$ROOT/proc"
	mounted "$ROOT/sys" || mount -t sysfs sysfs "$ROOT/sys"
	if [ -d /data/media/0 ]; then
		mkdir -p "$ROOT/sdcard"
		mounted "$ROOT/sdcard" || mount -o bind /data/media/0 "$ROOT/sdcard"
	fi
}

umount_all() {
	# deepest first
	grep -o " ${ROOT}[^ ]* " /proc/mounts | tr -d ' ' | awk '{ print length, $0 }' |
		sort -rn | cut -d' ' -f2- | while read -r m; do
		umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || warn "still busy: $m"
	done
}

# run_in <shell command> - inside the chroot, clean environment
run_in() {
	mount_all
	chroot "$ROOT" /usr/bin/env -i \
		HOME=/root TERM="${TERM:-xterm-256color}" LANG=C.UTF-8 \
		PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
		DEBIAN_FRONTEND=noninteractive \
		/bin/bash -lc "$1"
}

setup_rootfs() {
	# can be a symlink into /run that doesn't exist in a chroot
	rm -f "$ROOT/etc/resolv.conf"
	for d in $DNS; do echo "nameserver $d"; done > "$ROOT/etc/resolv.conf"
	echo flashbench > "$ROOT/etc/hostname"
	printf '127.0.0.1 localhost\n127.0.1.1 flashbench\n::1 localhost ip6-localhost\n' > "$ROOT/etc/hosts"

	# Android only lets these groups open sockets; apt drops to _apt to download
	for g in aid_inet:3003 aid_net_raw:3004 aid_net_admin:3005; do
		grep -q "^${g%%:*}:" "$ROOT/etc/group" ||
			echo "${g%%:*}:x:${g#*:}:root,_apt" >> "$ROOT/etc/group"
	done

	# no init in a chroot, package scripts must not try to start services
	printf '#!/bin/sh\nexit 101\n' > "$ROOT/usr/sbin/policy-rc.d"
	chmod 755 "$ROOT/usr/sbin/policy-rc.d"

	rm -f "$ROOT/etc/apt/sources.list"
	cat > "$ROOT/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: $MIRROR
Suites: noble noble-updates noble-backports noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
}

install_base() {
	need_root
	mkdir -p "$DDIR"
	[ "$(free_mb "$DDIR")" -ge 1024 ] 2>/dev/null || die "need at least 1 GB free on /data"

	msg "- looking up the latest 24.04 base image"
	sums=$(fb_fetch "$BASE_URL/SHA256SUMS") || die "cannot reach cdimage.ubuntu.com"
	pick=$(printf '%s\n' "$sums" |
		sed -n 's/^\([0-9a-f]\{64\}\) \*\(ubuntu-base-24\.04\.\([0-9]*\)-base-arm64\.tar\.gz\)$/\3 \1 \2/p' |
		sort -n | tail -n 1)
	[ -n "$pick" ] || die "no arm64 image listed in SHA256SUMS"
	read -r _ sha file <<EOF
$pick
EOF

	msg "- downloading $file"
	get "$BASE_URL/$file" "$DDIR/$file.part" || die "download failed, run install again to resume"
	got=$(sha256sum "$DDIR/$file.part" | cut -d' ' -f1)
	[ "$got" = "$sha" ] || { rm -f "$DDIR/$file.part"; die "sha256 mismatch, download is broken"; }

	msg "- unpacking"
	mkdir -p "$ROOT"
	$(tar_bin) -xpzf "$DDIR/$file.part" -C "$ROOT" || die "unpack failed"
	rm -f "$DDIR/$file.part"
	echo "$file" > "$DDIR/image"
	setup_rootfs
	msg "- updating the base system"
	run_in 'apt-get update -q && apt-get -y -q upgrade' || die "apt failed, check network/DNS (FB_DNS=...)"
}

sync_list() {
	installed || die "not installed, run: fb distro install"
	if [ "$(free_mb "$ROOT")" -lt 8192 ] 2>/dev/null; then
		warn "less than 8 GB free on /data, the full list takes about 6-8 GB"
	fi
	pkgs=$(cat "$LIST" "$EXTRA" 2>/dev/null | sed 's/#.*//' | tr -s ' \t' '\n' | grep . | sort -u | tr '\n' ' ')
	run_in "
		apt-get update -q || exit 1
		ok='' miss=''
		for p in $pkgs; do
			if apt-cache show \"\$p\" >/dev/null 2>&1; then ok=\"\$ok \$p\"; else miss=\"\$miss \$p\"; fi
		done
		[ -n \"\$miss\" ] && echo \"not in the archive, skipped:\$miss\"
		apt-get install -y -q --no-install-recommends \$ok && apt-get clean
	"
}

status() {
	if ! installed; then
		msg "not installed ($ROOT)"
		return 0
	fi
	msg "image   $(cat "$DDIR/image" 2>/dev/null)"
	msg "rootfs  $ROOT ($(du -sh "$ROOT" 2>/dev/null | cut -f1))"
	msg "free    $(free_mb "$DDIR") MB on /data"
	m=$(grep -o " ${ROOT}[^ ]* " /proc/mounts | tr -d ' ')
	if [ -n "$m" ]; then msg "mounted"; printf '%s\n' "$m" | sed 's/^/  /'; else msg "not mounted"; fi
}

remove() {
	need_root
	[ -d "$ROOT" ] || { msg "nothing to remove"; return 0; }
	umount_all
	# never rm -rf while /dev, /sys or the sdcard are still bound inside
	if grep -q " $ROOT" /proc/mounts; then
		die "something is still mounted under $ROOT, close shells inside it and retry"
	fi
	confirm "this deletes $ROOT ($(du -sh "$ROOT" 2>/dev/null | cut -f1)) and everything installed in it" ||
		die "cancelled"
	rm -rf "$ROOT" "$DDIR/image"
	msg "removed"
}

cmd=$1
[ -n "$cmd" ] && shift
case $cmd in
	install)
		need_root
		if installed; then msg "- already installed, checking packages"; else install_base; fi
		[ "$1" = --base ] && { msg "- base system ready: fb distro enter"; exit 0; }
		sync_list
		msg "- done: fb distro enter"
		;;
	''|enter|shell)
		need_root
		mount_all
		chroot "$ROOT" /usr/bin/env -i \
			HOME=/root TERM="${TERM:-xterm-256color}" LANG=C.UTF-8 \
			PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
			/bin/bash -l
		;;
	run)
		need_root
		[ $# -gt 0 ] || die "run what?"
		run_in "$*"
		;;
	apt)
		need_root
		run_in "apt-get $*"
		;;
	sync) need_root; sync_list ;;
	status) status ;;
	umount) need_root; umount_all ;;
	remove) remove ;;
	-h|--help|help) usage ;;
	*) usage; exit 1 ;;
esac
