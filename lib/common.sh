# shellcheck shell=bash
# build.sh helpers (host side). @Dev_DcS

if [ -t 2 ]; then
	c_dim=$'\e[2m' c_red=$'\e[31m' c_grn=$'\e[32m' c_ylw=$'\e[33m' c_off=$'\e[0m'
else
	c_dim='' c_red='' c_grn='' c_ylw='' c_off=''
fi

say()  { printf '%s>>%s %s\n' "$c_grn" "$c_off" "$*" >&2; }
note() { printf '%s   %s%s\n' "$c_dim" "$*" "$c_off" >&2; }
warn() { printf '%s!!%s %s\n' "$c_ylw" "$c_off" "$*" >&2; }
die()  { printf '%sxx%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

sha256() { sha256sum "$1" | cut -d' ' -f1; }

# components.list -> C_KIND[name] C_SRC[name] ... keeps file order in C_ORDER
declare -gA C_KIND C_SRC C_REF C_PIN C_WATCH C_FILTER C_HOLD
declare -ga C_ORDER=()

load_components() {
	local f name kind src ref pin watch filter hold
	for f in "$@"; do
		[ -f "$f" ] || continue
		while IFS='|' read -r name kind src ref pin watch filter hold; do
			case $name in ''|'#'*) continue ;; esac
			[ -n "${C_KIND[$name]:-}" ] || C_ORDER+=("$name")
			C_KIND[$name]=$kind C_SRC[$name]=$src C_REF[$name]=$ref C_PIN[$name]=$pin
			C_WATCH[$name]=$watch C_FILTER[$name]=$filter C_HOLD[$name]=$hold
		done < "$f"
	done
}

recipe_file() {
	local r
	for r in "$ROOT/private/recipes/$1.sh" "$ROOT/recipes/$1.sh"; do
		[ -f "$r" ] && { echo "$r"; return 0; }
	done
	return 1
}

# reads a variable out of a recipe without running build()
recipe_var() {
	( deps='' provides='' license='' hostneeds=''
	  # shellcheck disable=SC1090
	  . "$1"
	  eval "printf '%s' \"\${$2:-}\"" )
}

# depth-first, deps before dependents, each name once
declare -gA _seen
resolve() {
	local n r d
	for n in "$@"; do
		[ "${_seen[$n]:-}" = "done" ] && continue
		[ "${_seen[$n]:-}" = busy ] && die "dependency loop at $n"
		r=$(recipe_file "$n") || die "no recipe for '$n'"
		[ -n "${C_KIND[$n]:-}" ] || die "'$n' is missing from components.list"
		_seen[$n]=busy
		for d in $(recipe_var "$r" deps); do resolve "$d"; done
		_seen[$n]="done"
		ORDER+=("$n")
	done
}

fetch_component() {
	local n=$1 kind=${C_KIND[$1]} src=${C_SRC[$1]} ref=${C_REF[$1]} pin=${C_PIN[$1]}
	local dst="$WORK/src/$n" file got

	case $kind in
	git)
		# tihmstar's stuff versions itself off `git rev-list --count HEAD`, so a
		# shallow clone reports version 1 and the dependents' "libfoo >= 92"
		# checks fail. deep=1 pulls full history for those. everything else: shallow.
		local deep; deep=$(recipe_var "$(recipe_file "$n")" deep)
		if [ -d "$dst/.git" ] && [ "$(git -C "$dst" rev-parse HEAD 2>/dev/null)" = "$pin" ]; then
			# shallow checkout won't cut it for a deep recipe
			if [ "$deep" = 1 ] && [ -f "$dst/.git/shallow" ]; then
				git -C "$dst" fetch -q --unshallow 2>/dev/null || true
			else
				return 0
			fi
			return 0
		fi
		rm -rf "$dst"
		note "clone $src @ $ref"
		if [ "$deep" = 1 ]; then
			git clone -q "$src" "$dst" || die "$n: clone failed"
		else
			git clone -q --depth 1 --branch "$ref" "$src" "$dst" 2>/dev/null ||
				git clone -q "$src" "$dst" || die "$n: clone failed"
		fi
		got=$(git -C "$dst" rev-parse HEAD)
		if [ "$got" != "$pin" ]; then
			# branch moved or tag got re-pointed, try to get the exact pin.
			# never --depth on a deep clone: it turns it shallow again and the
			# commit count drops to 1 (libgeneral reported "1", img4tool died)
			if [ "$deep" = 1 ]; then
				git -C "$dst" cat-file -e "$pin^{commit}" 2>/dev/null ||
					git -C "$dst" fetch -q origin "$pin" 2>/dev/null || true
			else
				git -C "$dst" fetch -q --depth 1 origin "$pin" 2>/dev/null ||
					git -C "$dst" fetch -q --unshallow 2>/dev/null || true
			fi
			git -C "$dst" -c advice.detachedHead=false checkout -q "$pin" 2>/dev/null ||
				die "$n: $ref is at $got, pinned $pin is not reachable"
		fi
		;;
	tar|zip|apk|raw)
		file="$WORK/dl/${src##*/}"
		if [ ! -f "$file" ] || [ "$(sha256 "$file")" != "$pin" ]; then
			note "download ${src##*/}"
			curl -fL --retry 3 -s -o "$file.part" "$src" || die "$n: download failed"
			mv "$file.part" "$file"
		fi
		got=$(sha256 "$file")
		[ "$got" = "$pin" ] || die "$n: sha256 mismatch ($got)"
		[ -f "$dst/.fb-pin" ] && [ "$(cat "$dst/.fb-pin")" = "$pin" ] && return 0
		rm -rf "$dst"; mkdir -p "$dst"
		case $kind in
		tar) tar -xf "$file" -C "$dst" --strip-components=1 ;;
		zip) unzip -q "$file" -d "$dst.tmp" && mv "$dst.tmp"/*/* "$dst"/ && rm -rf "$dst.tmp" ;;
		apk) cp "$file" "$dst/" ;;
		# raw: a single prebuilt file (e.g. an NDK binary), kept under its own name
		raw) cp "$file" "$dst/${src##*/}" ;;
		esac
		echo "$pin" > "$dst/.fb-pin"
		;;
	local)
		[ -d "$ROOT/$src" ] || die "$n: $src not found"
		rm -rf "$dst"
		cp -a "$ROOT/$src" "$dst"
		;;
	*) die "$n: unknown kind '$kind'" ;;
	esac

	apply_patches "$n" "$dst"
}

apply_patches() {
	local p d
	for d in "$ROOT/patches/$1" "$ROOT/private/patches/$1"; do
		[ -d "$d" ] || continue
		for p in "$d"/*.patch; do
			[ -f "$p" ] || continue
			[ -f "$2/.fb-patched-${p##*/}" ] && continue
			note "patch ${p##*/}"
			patch -d "$2" -p1 -s < "$p" || die "$1: ${p##*/} does not apply"
			: > "$2/.fb-patched-${p##*/}"
		done
	done
}

# anything that changes the output of a component changes this
stamp_of() {
	local n=$1 r d
	r=$(recipe_file "$n")
	{
		printf '%s\n' "${C_PIN[$n]}" "$TC_ID"
		cat "$r"
		if [ "${C_KIND[$n]}" = local ]; then
			find "$ROOT/${C_SRC[$n]}" -type f | sort | xargs cat
		fi
		for d in "$ROOT/patches/$n" "$ROOT/private/patches/$n"; do
			[ -d "$d" ] && cat "$d"/*.patch 2>/dev/null || :
		done
		for d in $(recipe_var "$r" deps); do cat "$WORK/stamps/$d" 2>/dev/null || :; done
	} | sha256sum | cut -d' ' -f1
}
