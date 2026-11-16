#!/usr/bin/env bash
# FlashBench builder - @Dev_DcS
#
#   ./build.sh                     public profile, everything it lists
#   ./build.sh -p master           private/profiles/master.conf (not in git)
#   ./build.sh -p public qdl       just qdl (+ its deps), no zip
#   ./build.sh --list              what a profile pulls in
#
# work/ holds sources, toolchain, prefix and stamps, out/ gets the zips.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
WORK=${FB_WORK:-$ROOT/work}
OUTDIR=${FB_OUT:-$ROOT/out}

# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=lib/toolchain.sh
. "$ROOT/lib/toolchain.sh"

usage() {
	cat <<-EOF
	usage: ${0##*/} [-p profile] [options] [component...]

	  -p, --profile NAME   public (default), master, or any profiles/NAME.conf
	  -j, --jobs N         parallel jobs (default: $(nproc))
	  -l, --list           print the resolved component list and exit
	  -f, --fetch-only     download + verify sources, no compiling
	  -k, --package-only   skip building, zip what is already built
	  -c, --clean          wipe work/ first
	      --no-zip         build only
	  -h, --help

	components given on the command line replace the profile list (implies --no-zip)
	EOF
}

profile=public
JOBS=$(nproc)
list=0 fetch_only=0 pkg_only=0 clean=0 no_zip=0
picked=()

while [ $# -gt 0 ]; do
	case $1 in
		-p|--profile) profile=$2; shift ;;
		-j|--jobs) JOBS=$2; shift ;;
		-l|--list) list=1 ;;
		-f|--fetch-only) fetch_only=1 ;;
		-k|--package-only) pkg_only=1 ;;
		-c|--clean) clean=1 ;;
		--no-zip) no_zip=1 ;;
		-h|--help) usage; exit 0 ;;
		-*) usage; exit 1 ;;
		*) picked+=("$1") ;;
	esac
	shift
done
[ ${#picked[@]} -gt 0 ] && no_zip=1

# --- profile -------------------------------------------------------------

load_profile() {
	local f found=''
	for f in "$ROOT/config/profiles/$1.conf" "$ROOT/private/profiles/$1.conf"; do
		# later file wins, so a private copy can override a public profile
		# shellcheck disable=SC1090
		[ -f "$f" ] && { . "$f"; found=$f; }
	done
	[ -n "$found" ] || die "profile '$1' not found (config/profiles or private/profiles)"
	PROFILE=$1 PROFILE_FILE=$found
	# secrets/local settings never committed
	# shellcheck disable=SC1091
	[ -f "$ROOT/private/env" ] && . "$ROOT/private/env"
	: "${MOD_ID:?}" "${MOD_NAME:?}" "${COMPONENTS:?}"
	: "${MOD_DESC:=}" "${UPDATE_JSON:=}" "${VERSION_SUFFIX:=}" "${FEATURES:=}"
	: "${WATCH_DEFAULT:=0}" "${NOTIFY_DEFAULT:=android}" "${NTFY_URL:=}" "${MODULE_OVERLAY:=}"
}

load_profile "$profile"
# shellcheck disable=SC1091
. "$ROOT/config/version"
load_components "$ROOT/config/components.list" "$ROOT/private/components.list"

if [ ${#picked[@]} -gt 0 ]; then
	want=("${picked[@]}")
elif [ "$COMPONENTS" = all ]; then
	want=()
	for n in "${C_ORDER[@]}"; do
		r=$(recipe_file "$n") || continue
		[ -n "$(recipe_var "$r" provides)" ] && want+=("$n")
	done
else
	read -ra want <<< "$COMPONENTS"
fi

ORDER=()
resolve "${want[@]}"

if [ $list = 1 ]; then
	printf 'profile %s (%s)\n' "$PROFILE" "${PROFILE_FILE#"$ROOT"/}"
	for n in "${ORDER[@]}"; do
		printf '  %-18s %-14s %s\n' "$n" "${C_REF[$n]}" "$(recipe_var "$(recipe_file "$n")" provides)"
	done
	exit 0
fi

# --- host check ----------------------------------------------------------

need=(git curl unzip tar patch make cmake ninja pkg-config readelf sha256sum zip python3)
for n in "${ORDER[@]}"; do
	# recipes declare their own host tools; keep a few name-based fallbacks
	for h in $(recipe_var "$(recipe_file "$n")" hostneeds); do need+=("$h"); done
	case $n in
		qdl) need+=(meson) ;;
		libusb|strace|curl|libplist|limd-glue|libgeneral|libusbmuxd|libtatsu|libirecovery|libimobiledevice|img4tool|img3tool) need+=(autoreconf) ;;
		payload-dumper-go) need+=(go) ;;
		samloader-rs|penumbra|idevice) need+=(cargo) ;;
	esac
done
miss=()
for t in "${need[@]}"; do have "$t" || miss+=("$t"); done
[ ${#miss[@]} -eq 0 ] || die "missing host tools: ${miss[*]}"

[ $clean = 1 ] && { say "clean"; rm -rf "$WORK"; }
mkdir -p "$WORK"/{dl,src,build,bin,stamps} "$OUTDIR"

setup_toolchain
say "toolchain $TC_ID"

# --- build ---------------------------------------------------------------

build_component() {
	local n=$1 r stamp b rc
	r=$(recipe_file "$n")
	stamp=$(stamp_of "$n")
	if [ -f "$WORK/stamps/$n" ] && [ "$(cat "$WORK/stamps/$n")" = "$stamp" ]; then
		note "$n up to date"
		return 0
	fi
	say "build $n ${C_REF[$n]}"
	rm -rf "$WORK/build/${n:?}" "$WORK/bin/${n:?}"
	mkdir -p "$WORK/build/$n"
	cp -a "$WORK/src/$n" "$WORK/build/$n/src"
	# careful: don't do `( ... ) || die`. posix turns off errexit inside a
	# subshell that's on the left of || so a broken build sails through (lost a
	# day to this). run it bare, grab the code, check it ourselves.
	rc=0
	set +e
	(
		set -e
		SRC="$WORK/build/$n/src" BLD="$WORK/build/$n/obj" OUT="$WORK/bin/$n"
		REF=${C_REF[$n]} PIN=${C_PIN[$n]}
		export SRC BLD OUT REF PIN JOBS
		deps='' provides='' hostneeds=''
		# shellcheck disable=SC1090
		. "$r"
		cd "$SRC"
		build
	) > "$WORK/build/$n.log" 2>&1
	rc=$?
	set -e
	if [ $rc -ne 0 ]; then
		tail -n 40 "$WORK/build/$n.log" >&2
		die "$n failed, full log: ${WORK#"$ROOT"/}/build/$n.log"
	fi
	# if a recipe says it provides X, X had better be there (catches bad
	# put_bin paths that would otherwise ship a zip missing binaries)
	for b in $(recipe_var "$r" provides); do
		[ -f "$WORK/bin/$n/bin/$b" ] || die "$n built but no '$b' - wrong put_bin path in recipes/$n.sh?"
	done
	echo "$stamp" > "$WORK/stamps/$n"
}

if [ $pkg_only = 0 ]; then
	for n in "${ORDER[@]}"; do fetch_component "$n"; done
	[ $fetch_only = 1 ] && { say "sources ok"; exit 0; }
	for n in "${ORDER[@]}"; do build_component "$n"; done
fi

# --- verify --------------------------------------------------------------

# must be static aarch64 and survive a 16k page kernel (which also means 4k).
# every LOAD: align divisible by 16k, and offset==vaddr mod 16k.
check_elf() {
	local f=$1 hdr off va al
	hdr=$(readelf -hlW "$f" 2>/dev/null) || { echo "not ELF"; return 1; }
	grep -q 'Machine:.*AArch64' <<< "$hdr" || { echo "not aarch64"; return 1; }
	grep -q 'INTERP' <<< "$hdr" && { echo "dynamic"; return 1; }
	while read -r off va al; do
		[ $((al % 16384)) -eq 0 ] || { echo "LOAD align $al, no good on 16k"; return 1; }
		[ $(((va - off) % 16384)) -eq 0 ] || { echo "LOAD off/vaddr not congruent mod 16k"; return 1; }
	done < <(awk '$1 == "LOAD" { print $2, $3, $NF }' <<< "$hdr")
	return 0
}

say "verify binaries"
bad=0
for n in "${ORDER[@]}"; do
	for f in "$WORK/bin/$n/bin"/*; do
		[ -f "$f" ] || continue
		"$STRIP" --strip-all "$f" 2>/dev/null || true
		if why=$(check_elf "$f"); then
			note "$(printf '%-20s %6s KiB  4K+16K ok' "${f##*/}" $(( $(stat -c %s "$f") / 1024 )))"
		else
			warn "${f##*/}: $why"; bad=1
		fi
	done
done
[ $bad = 0 ] || die "binary checks failed"

[ $no_zip = 1 ] && { say "done (no zip)"; exit 0; }

# --- package -------------------------------------------------------------

PKG="$WORK/pkg/$PROFILE"
VER="v$VERSION$VERSION_SUFFIX"
ZIP="$OUTDIR/$MOD_NAME-$VER.zip"

say "package $VER ($PROFILE)"
rm -rf "$PKG"; mkdir -p "$PKG"
cp -a "$ROOT/module/." "$PKG/"
if [ -n "$MODULE_OVERLAY" ]; then
	if [ -d "$ROOT/$MODULE_OVERLAY" ]; then
		cp -a "$ROOT/$MODULE_OVERLAY/." "$PKG/"
	else
		warn "overlay $MODULE_OVERLAY not found, skipped"
	fi
fi
find "$PKG" -name .keep -delete
mkdir -p "$PKG/system/bin" "$PKG/licenses"

# drop toolkit parts the profile does not want
for f in "$PKG"/libexec/fb-*.sh; do
	feat=${f##*/fb-}; feat=${feat%.sh}
	case " $FEATURES " in *" $feat "*) ;; *) rm -f "$f" ;; esac
done

for n in "${ORDER[@]}"; do
	for f in "$WORK/bin/$n/bin"/*; do
		[ -f "$f" ] || continue
		case ${f##*/} in
			# these read HOME/TMPDIR, the real binary hides behind a wrapper
			adb|fastboot) install -m 755 "$f" "$PKG/system/bin/.${f##*/}" ;;
			*) install -m 755 "$f" "$PKG/system/bin/" ;;
		esac
	done
	if [ -d "$WORK/bin/$n/license" ]; then
		mkdir -p "$PKG/licenses/$n"
		cp -a "$WORK/bin/$n/license/." "$PKG/licenses/$n/"
	fi
	if [ -d "$WORK/bin/$n/asset" ]; then
		mkdir -p "$PKG/share"
		cp -a "$WORK/bin/$n/asset/." "$PKG/share/"
	fi
	if [ -d "$WORK/bin/$n/python" ]; then
		mkdir -p "$PKG/python"
		cp -a "$WORK/bin/$n/python/." "$PKG/python/"
	fi
	# a recipe may drop files straight into the module's system/ overlay
	if [ -d "$WORK/bin/$n/system" ]; then
		cp -a "$WORK/bin/$n/system/." "$PKG/system/"
	fi
done
for t in adb fastboot; do
	[ -f "$PKG/system/bin/.$t" ] && sed "s/@BIN@/$t/" "$PKG/wrap.in" > "$PKG/system/bin/$t"
done
rm -f "$PKG/wrap.in"
sed "s/@MODID@/$MOD_ID/" "$PKG/fb" > "$PKG/system/bin/fb" && rm -f "$PKG/fb"
chmod 755 "$PKG"/system/bin/*

{
	echo "id=$MOD_ID"
	echo "name=$MOD_NAME"
	echo "version=$VER"
	echo "versionCode=$VERSION_CODE"
	echo "author=@Dev_DcS"
	echo "description=$MOD_DESC"
	[ -n "$UPDATE_JSON" ] && echo "updateJson=$UPDATE_JSON"
} > "$PKG/module.prop"

cat > "$PKG/fb.conf.default" <<-EOF
# FlashBench settings, lives in /data/local/tmp/flashbench/fb.conf after install
watch=$WATCH_DEFAULT
watch_interval=43200
notify=$NOTIFY_DEFAULT
ntfy_url=$NTFY_URL
doh_url=https://1.1.1.1/dns-query
EOF

# only what this zip contains, so fb watch reports on the right things
for n in "${ORDER[@]}"; do
	printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$n" "${C_KIND[$n]}" "${C_SRC[$n]}" "${C_REF[$n]}" \
		"${C_PIN[$n]}" "${C_WATCH[$n]}" "${C_FILTER[$n]}" "${C_HOLD[$n]}"
done > "$PKG/components.list"

{
	echo "profile=$PROFILE"
	echo "version=$VER ($VERSION_CODE)"
	echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "tree=$(git -C "$ROOT" describe --always --dirty 2>/dev/null || echo none)"
	echo "toolchain=$TC_ID"
	echo
	for n in "${ORDER[@]}"; do echo "src $n ${C_REF[$n]} ${C_PIN[$n]}"; done
	echo
	(cd "$PKG/system/bin" && find . -maxdepth 1 -type f ! -name fb ! -name adb ! -name fastboot \
		-exec sha256sum {} + | sed 's|\./||' | sort -k2 | sed 's/^/bin /')
} > "$PKG/build.info"

find "$PKG" -name '*.sh' -exec sed -i 's/\r$//' {} +
rm -f "$ZIP"
(cd "$PKG" && zip -qr9X "$ZIP" .)
say "$ZIP ($(( $(stat -c %s "$ZIP") / 1024 / 1024 )) MiB)"
