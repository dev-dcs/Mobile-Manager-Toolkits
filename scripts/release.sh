#!/usr/bin/env bash
# release helper - @Dev_DcS
#
#   scripts/release.sh bump [patch|minor|major]   new version in config/version + CHANGELOG stub
#   scripts/release.sh json                       print update.json for the current version
#   scripts/release.sh publish <zip>              (CI) GitHub release + update.json on the default branch

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=${GITHUB_REPOSITORY:-dev-dcs/Mobile-Manager-Toolkits}
cd "$ROOT"
# shellcheck disable=SC1091
. config/version

json() {
	cat <<-EOF
	{
	  "version": "v$VERSION",
	  "versionCode": $VERSION_CODE,
	  "zipUrl": "https://github.com/$REPO/releases/download/v$VERSION/FlashBench-v$VERSION.zip",
	  "changelog": "https://raw.githubusercontent.com/$REPO/main/CHANGELOG.md"
	}
	EOF
}

case ${1:-} in
bump)
	IFS=. read -r ma mi pa <<< "$VERSION"
	case ${2:-patch} in
		major) ma=$((ma + 1)) mi=0 pa=0 ;;
		minor) mi=$((mi + 1)) pa=0 ;;
		patch) pa=$((pa + 1)) ;;
		*) echo "patch, minor or major" >&2; exit 1 ;;
	esac
	VERSION=$ma.$mi.$pa
	VERSION_CODE=$((ma * 10000 + mi * 100 + pa))
	printf 'VERSION=%s\nVERSION_CODE=%s\n' "$VERSION" "$VERSION_CODE" > config/version
	{ printf '## v%s\n\n- \n\n' "$VERSION"; cat CHANGELOG.md; } > CHANGELOG.md.new && mv CHANGELOG.md.new CHANGELOG.md
	echo "v$VERSION ($VERSION_CODE). Fill CHANGELOG.md, commit, then: git tag v$VERSION && git push --tags"
	;;
json)
	json
	;;
publish)
	zip=${2:?zip path}
	tag=v$VERSION
	[ "${GITHUB_REF_NAME:-$tag}" = "$tag" ] || { echo "tag ${GITHUB_REF_NAME} does not match config/version $tag" >&2; exit 1; }
	notes=$(awk -v v="## $tag" '$0 == v { on = 1; next } /^## / && on { exit } on' CHANGELOG.md)
	gh release create "$tag" "$zip" --title "FlashBench $tag" --notes "${notes:-$tag}"

	# managers only see the new version once the zip is downloadable
	git config user.name "${GIT_AUTHOR_NAME:-github-actions[bot]}"
	git config user.email "${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
	branch=$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)
	git fetch -q origin "$branch"
	git checkout -q -B "$branch" "origin/$branch"
	json > update.json
	git add update.json
	git commit -q -m "update.json: $tag" && git push -q origin "$branch" || echo "update.json unchanged"
	;;
*)
	sed -n '2,7p' "$0"
	exit 1
	;;
esac
