# upstream release check, shared by fb watch (device) and scripts/upstream-check.sh (CI)
# @Dev_DcS
# shellcheck shell=sh
#
# needs: awk, sed, and either git or an http fetcher passed as UP_FETCH
# (a command that prints the body of the url given as $1)

UP_FETCH=${UP_FETCH:-}

# up_refs <repo url> -> "sha ref" lines, tags and branch heads only
up_refs() {
	if command -v git >/dev/null 2>&1; then
		GIT_TERMINAL_PROMPT=0 git ls-remote --tags --heads "$1" 2>/dev/null
		return
	fi
	[ -n "$UP_FETCH" ] || return 1
	u=${1%/}
	case $u in https://github.com/*) case $u in *.git) ;; *) u=$u.git ;; esac ;; esac
	# smart http ref advertisement, pkt-line framed: "<4 hex len><sha> <ref>"
	$UP_FETCH "$u/info/refs?service=git-upload-pack" | tr '\000' ' ' | awk '
		{
			while ($0 ~ /^0000/) $0 = substr($0, 5)
			if ($0 !~ /^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/) next
			l = substr($0, 5)
			split(l, f, " ")
			if (f[2] ~ /^refs\/(tags|heads)\//) print f[1], f[2]
		}'
}

# up_latest <filter regex> < refs -> "tag sha" of the highest matching tag
# versions compare field by field on their digit runs, so
# pcre2-10.45 < pcre2-10.47 and 37.0.0 < 37.0.0p1
up_latest() {
	UP_RE=$1 awk '
		function vkey(s,   n, i, a, out) {
			gsub(/[^0-9]+/, " ", s)
			n = split(s, a, " ")
			out = ""
			for (i = 1; i <= n; i++) out = out sprintf("%010d.", a[i])
			return out
		}
		BEGIN { re = ENVIRON["UP_RE"] }
		$2 ~ /^refs\/tags\// {
			t = $2; sub(/^refs\/tags\//, "", t)
			peeled = sub(/\^\{\}$/, "", t)
			if (t !~ re) next
			if (peeled || !(t in sha)) sha[t] = $1
			k = vkey(t)
			if (best == "" || k > bestk) { best = t; bestk = k }
		}
		END { if (best != "") print best, sha[best] }'
}

up_newer() {
	# true if $2 sorts above $1 with the same rule as up_latest
	awk -v a="$1" -v b="$2" '
		function vkey(s,   n, i, x, out) {
			gsub(/[^0-9]+/, " ", s); n = split(s, x, " "); out = ""
			for (i = 1; i <= n; i++) out = out sprintf("%010d.", x[i])
			return out
		}
		BEGIN { exit !(vkey(b) > vkey(a)) }'
}

# up_page <url> - plain page body, for index: watches
up_page() {
	if [ -n "$UP_FETCH" ]; then
		$UP_FETCH "$1"
	elif command -v curl >/dev/null 2>&1; then
		curl -fsSL -m 30 "$1"
	else
		return 1
	fi
}

# up_check <components.list line>
#   -> name|status|current|latest|note   status: ok update held moved error
up_check() {
	IFS='|' read -r n kind src ref pin watch filter hold <<EOF
$1
EOF
	[ "$kind" = local ] && return 0
	[ "$watch" = - ] && watch=$src

	case $filter in index:*)
		re=${filter#index:}
		set -- $(up_page "$watch" | grep -oE "$re" | sed -E "s/$re/\1/" |
			sed 's|^|0 refs/tags/|' | up_latest '.')
		if [ -z "$1" ]; then
			echo "$n|error|$ref||nothing matching on $watch"
		elif up_newer "$ref" "$1"; then
			echo "$n|update|$ref|$1|"
		else
			echo "$n|ok|$ref|$1|"
		fi
		return
	esac

	refs=$(up_refs "$watch") || refs=
	if [ -z "$refs" ]; then
		echo "$n|error|$ref||no answer from $watch"
		return
	fi

	case $filter in
	branch:*)
		b=${filter#branch:}
		head=$(echo "$refs" | awk -v r="refs/heads/$b" '$2 == r { print $1 }')
		if [ -z "$head" ]; then
			echo "$n|error|$ref||branch $b not found"
		elif [ "$head" = "$pin" ]; then
			echo "$n|ok|$b@$(echo "$pin" | cut -c1-7)|$b@$(echo "$head" | cut -c1-7)|"
		else
			echo "$n|moved|$b@$(echo "$pin" | cut -c1-7)|$b@$(echo "$head" | cut -c1-7)|new commits on $b"
		fi
		;;
	*)
		set -- $(echo "$refs" | up_latest "$filter")
		if [ -z "$1" ]; then
			echo "$n|error|$ref||no tag matches $filter"
		elif up_newer "$ref" "$1"; then
			if [ -n "$hold" ]; then
				echo "$n|held|$ref|$1|$hold"
			else
				echo "$n|update|$ref|$1|$2"
			fi
		else
			echo "$n|ok|$ref|$1|"
		fi
		;;
	esac
}

# up_check_all <components.list> -> one result line per component
up_check_all() {
	grep -v '^[[:space:]]*#' "$1" | grep '|' | while IFS= read -r line; do
		up_check "$line"
	done
}
