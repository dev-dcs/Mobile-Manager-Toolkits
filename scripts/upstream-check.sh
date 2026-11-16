#!/usr/bin/env bash
# upstream-check - same check fb watch does on the phone, for CI and local use
# @Dev_DcS
#
#   scripts/upstream-check.sh              table on stdout
#   scripts/upstream-check.sh --md f.md    also write a markdown report
#   scripts/upstream-check.sh --issue      open/refresh/close the "upstream" issue (gh)
#   scripts/upstream-check.sh --write      bump git pins in config/components.list
#
# exit code 0, or 10 with --exit-code when something has an update

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../module/lib/upstream.sh
. "$ROOT/module/lib/upstream.sh"

md='' issue=0 write=0 exitcode=0
while [ $# -gt 0 ]; do
	case $1 in
		--md) md=$2; shift ;;
		--issue) issue=1 ;;
		--write) write=1 ;;
		--exit-code) exitcode=1 ;;
		-h|--help) sed -n '2,11p' "$0"; exit 0 ;;
		*) echo "unknown option $1" >&2; exit 1 ;;
	esac
	shift
done

# public list, private one overrides by name
list=$(mktemp)
trap 'rm -f "$list"' EXIT
srcs=("$ROOT/config/components.list")
[ -f "$ROOT/private/components.list" ] && srcs+=("$ROOT/private/components.list")
awk -F'|' '
	/^[[:space:]]*#/ || !/\|/ { next }
	{ if (!($1 in row)) order[++n] = $1; row[$1] = $0 }
	END { for (i = 1; i <= n; i++) print row[order[i]] }
' "${srcs[@]}" > "$list"

res=$(up_check_all "$list")
printf '%s\n' "$res" | awk -F'|' '{ printf "%-18s %-7s %-16s %s\n", $1, $2, $3, ($2 == "ok" ? "" : $4) }'

pending=$(printf '%s\n' "$res" | awk -F'|' '$2 == "update" || $2 == "moved"')

report() {
	echo "| component | status | pinned | upstream | note |"
	echo "|---|---|---|---|---|"
	printf '%s\n' "$res" | awk -F'|' '$2 != "ok" { printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5 }'
	echo
	echo "_checked $(date -u +%Y-%m-%dT%H:%M:%SZ)_"
}

[ -n "$md" ] && report > "$md"

if [ $write = 1 ] && [ -n "$pending" ]; then
	printf '%s\n' "$pending" | while IFS='|' read -r n st cur new sha; do
		kind=$(awk -F'|' -v n="$n" '$1 == n { print $2 }' "$ROOT/config/components.list")
		if [ "$kind" = git ] && [ "$st" = update ]; then
			awk -F'|' -v OFS='|' -v n="$n" -v t="$new" -v s="$sha" \
				'$1 == n { $4 = t; $5 = s } { print }' "$ROOT/config/components.list" > "$list.w" &&
				mv "$list.w" "$ROOT/config/components.list"
			echo "bumped $n $cur -> $new"
		else
			echo "manual: $n $cur -> $new (${kind:-private} source, url/sha256 need a look)"
		fi
	done
fi

if [ $issue = 1 ]; then
	command -v gh >/dev/null || { echo "gh not found" >&2; exit 1; }
	title="Upstream updates for bundled tools"
	num=$(gh issue list --label upstream --state open --json number --jq '.[0].number' 2>/dev/null)
	if [ -n "$pending" ]; then
		gh label create upstream --color 0e8a16 --description "newer upstream release" >/dev/null 2>&1 || true
		body=$(report)
		if [ -n "$num" ]; then
			gh issue edit "$num" --body "$body" >/dev/null
		else
			gh issue create --title "$title" --label upstream --body "$body" >/dev/null
		fi
		if [ -n "${NTFY_URL:-}" ]; then
			curl -fsS -H "Title: FlashBench upstream" \
				-d "$(printf '%s\n' "$pending" | awk -F'|' '{printf "%s %s -> %s, ", $1, $3, $4}')" \
				"$NTFY_URL" >/dev/null || true
		fi
	elif [ -n "$num" ]; then
		gh issue close "$num" --comment "everything is current again" >/dev/null
	fi
fi

[ $exitcode = 1 ] && [ -n "$pending" ] && exit 10
exit 0
