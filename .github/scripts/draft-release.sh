#!/bin/bash
# Put a build into a DRAFT GitHub release, named after the release scheme:
#   lineageos  tag lineageos-22.2-YYYYMMDD[-N]   title "LineageOS 22.2 · YYYY-MM-DD[ (N)]"
#   nura       tag nura-YYYYMMDD[-N]             title "Nura (beta) · YYYY-MM-DD[ (N)]"
# -N counts further builds of the same day. Older unpublished drafts of the
# same system are deleted (only the newest draft stays). Publishing is done by
# hand on GitHub; latest.yml then refreshes the fixed "<system>-latest" release.
#
# Usage: draft-release.sh lineageos|nura DATE NOTES_FILE FILE...
# Needs: gh with GH_TOKEN, GITHUB_REPOSITORY.
set -euo pipefail
sys=$1 date=$2 notes=$3
shift 3
repo=${GITHUB_REPOSITORY:?}

case $sys in
	lineageos) prefix=lineageos-22.2 name="LineageOS 22.2" ;;
	nura) prefix=nura name="Nura (beta)" ;;
	*) echo "unknown system $sys" >&2; exit 2 ;;
esac

# all releases (drafts included) of this system: "tag<TAB>isDraft"
existing=$(gh release list --repo "$repo" --limit 200 --json tagName,isDraft \
	-q '.[] | "\(.tagName)\t\(.isDraft)"' | grep "^$prefix-[0-9]" || true)

# delete older drafts of this system
while IFS=$'\t' read -r tag draft; do
	[ "$draft" = true ] || continue
	echo "deleting older draft $tag"
	gh release delete "$tag" --repo "$repo" --yes
done <<< "$existing"

# next free tag for this date (published releases keep their tags)
tag=$prefix-$date
n=1
while gh release view "$tag" --repo "$repo" >/dev/null 2>&1 \
	|| git ls-remote --exit-code --tags "https://github.com/$repo" "refs/tags/$tag" >/dev/null 2>&1; do
	n=$((n + 1))
	tag=$prefix-$date-$n
done
title="$name · ${date:0:4}-${date:4:2}-${date:6:2}"
[ $n -gt 1 ] && title="$title ($n)"

gh release create "$tag" "$@" --repo "$repo" --draft --title "$title" \
	--notes-file "$notes" --target "${GITHUB_SHA:-main}"
echo "draft release $tag created"
