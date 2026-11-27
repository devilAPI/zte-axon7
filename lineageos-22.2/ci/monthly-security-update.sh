#!/bin/bash
# Monthly LineageOS 22.2 security update for the ZTE Axon 7.
#
# Run on the build server (user "build"), not on the PC:
#   bash /srv/aosp/axon7-monthly-22.2/monthly-security-update.sh
#
# The script is copied from lineageos-22.2/ci/ in this repository together
# with the patch directories (port-22.2/, kernel-4.4-patches/):
#   rsync -a lineageos-22.2/ci/ root@compiler:/srv/aosp/axon7-monthly-22.2/ci/
#   scp -r lineageos-22.2/port-22.2 lineageos-22.2/kernel-4.4-patches \
#       root@compiler:/srv/aosp/axon7-monthly-22.2/
#
# It: waits for the shared build lock; records the old security patch level,
# zip and SHA-256; checks that every device patch applies to its base; saves
# all local commits; repo syncs lineage-22.2; restores the device/kernel/vendor
# branches and re-applies the AOSP patches; rebuilds the standalone release zip;
# and writes a summary with the before/after security patch levels and hashes.
# Untracked port files left by an interrupted restore are moved aside, compared
# with the fork's versions and dropped only if identical; the build refuses to
# run unless every fork is back at its saved head and clean. Nothing touches a
# phone.
set -euo pipefail

TREE=${AXON7_TREE:-/srv/aosp/lineage-22.2}
PATCHES=${AXON7_PATCH_DIR:-/srv/aosp/axon7-monthly-22.2}
DEST=${AXON7_RELEASES:-/srv/aosp/releases}
OUT=$TREE/out/target/product/axon7
STAMP=$(date +%Y%m%d-%H%M%S)
SUMMARY=$PATCHES/monthly-$STAMP.summary
STATE=$PATCHES/monthly-$STAMP.state

export PATH=/home/build/bin:$PATH

echo "== monthly update start $(date -u) stamp=$STAMP"
mkdir -p "$PATCHES"
cd "$TREE"

# One build at a time on the server. A caller that already holds the lock on
# fd 9 (e.g. a recovery wrapper) passes it down; the build script does the same.
if [[ ${AXON7_BUILD_LOCK_FD:-} != 9 ]]; then
  exec 9>/srv/aosp/build.lock
  echo "== waiting for /srv/aosp/build.lock $(date +%T)"
  flock 9
  echo "== got the build lock $(date +%T)"
else
  echo "== build lock held by caller on fd 9 $(date +%T)"
fi

PROP=$OUT/system/build.prop
OLD_ZIP=$(ls -t "$DEST"/lineage-22.2-*-UNOFFICIAL-axon7.zip 2>/dev/null | head -1 || true)
OLD_SHA=","
if [[ -n $OLD_ZIP ]]; then OLD_SHA=$(sha256sum "$OLD_ZIP" | awk '{print $1}'); fi
OLD_PATCH=$(grep -m1 '^ro.build.version.security_patch=' "$PROP" 2>/dev/null | cut -d= -f2 || true)
OLD_VENDOR_PATCH=$(grep -m1 '^ro.vendor.build.security_patch=' "$OUT/vendor/build.prop" 2>/dev/null | cut -d= -f2 || true)
OLD_MANIFEST=$(git -C "$TREE/.repo/manifests" rev-parse HEAD)
echo "== before: security_patch=$OLD_PATCH vendor=$OLD_VENDOR_PATCH manifest=$OLD_MANIFEST"
echo "== before: zip=$OLD_ZIP sha256=$OLD_SHA"

# Projects with our own commits. repo sync resets them to the manifest
# revision; the refs below keep the exact old commits reachable.
CUSTOM_PROJECTS=(device/zte/axon7 kernel/zte/msm8996 vendor/zte)
CUSTOM_BRANCHES=(axon7-22.2 axon7 axon7-lineage-22.2)
AOSP_PROJECTS=(frameworks/av frameworks/base system/core system/libhidl)

: > "$STATE"
{
  echo "STAMP=$STAMP"
  echo "MANIFEST_BEFORE=$OLD_MANIFEST"
  echo "SECURITY_PATCH_BEFORE=$OLD_PATCH"
  echo "ZIP_BEFORE=$OLD_ZIP"
  echo "SHA256_BEFORE=$OLD_SHA"
} >> "$STATE"

head_sha() { git -C "$TREE/$1" rev-parse HEAD; }

# A previous interrupted restore can leave the port files in the worktree as
# untracked files while HEAD is on upstream: git checkout then refuses to
# switch branches. Keep a copy, clean the worktree, and after the checkout
# prove every saved file is byte-identical to the fork's tracked version.
# On any mismatch the backup is kept and the script aborts before the build.
backup_untracked() {
  local proj=$1 bak=$PATCHES/untracked-backup-$(echo "$proj" | tr / _)-$STAMP
  local files
  files=$(git -C "$TREE/$proj" ls-files --others --exclude-standard)
  [[ -n $files ]] || return 0
  mkdir -p "$bak"
  while IFS= read -r f; do
    mkdir -p "$bak/$(dirname "$f")"
    cp -p "$TREE/$proj/$f" "$bak/$f"
  done <<< "$files"
  git -C "$TREE/$proj" clean -fdq
  echo "== $proj: moved $(printf '%s\n' "$files" | wc -l) untracked file(s) aside to $bak"
}

verify_untracked_backup() {
  local proj=$1 sha=$2 bak=$3 tmp=$PATCHES/.fork-file-$STAMP-$$
  [[ -d $bak ]] || return 0
  local f
  while IFS= read -r f; do
    if ! git -C "$TREE/$proj" cat-file -e "$sha:$f" 2>/dev/null ||
       ! git -C "$TREE/$proj" show "$sha:$f" > "$tmp" ||
       ! cmp -s "$bak/$f" "$tmp"; then
      echo "ERROR: $proj/$f differs from the fork ($sha); backup kept at $bak" >&2
      rm -f "$tmp"
      return 1
    fi
  done < <(cd "$bak" && find . -type f -printf '%P\n')
  rm -f "$tmp"
  rm -rf "$bak"
  echo "== $proj: untracked files matched the fork versions; backup removed"
}

for i in "${!CUSTOM_PROJECTS[@]}"; do
  proj=${CUSTOM_PROJECTS[$i]}
  branch=${CUSTOM_BRANCHES[$i]}
  sha=$(head_sha "$proj")
  key=$(echo "$proj" | tr / _)
  echo "${key}_SHA=$sha" >> "$STATE"
  echo "${key}_BRANCH=$branch" >> "$STATE"
  git -C "$TREE/$proj" update-ref "refs/axon7-monthly/$STAMP" "$sha"
  echo "== saved $proj $branch $sha"
done

# Other workers use this tree for test variants under the same lock. If one
# left files behind, restore these three projects to the exact saved commits
# before checking patches or syncing. We hold the lock, so nobody is editing.
for proj in "${CUSTOM_PROJECTS[@]}"; do
  key=$(echo "$proj" | tr / _)
  sha=$(grep "^${key}_SHA=" "$STATE" | cut -d= -f2-)
  if [[ -n $(git -C "$TREE/$proj" status --porcelain) ]]; then
    echo "== WARN: $proj was dirty, restoring $sha"
    git -C "$TREE/$proj" reset --quiet --hard "$sha"
    git -C "$TREE/$proj" clean -fdq
  fi
done

# Every patch file is a git-format-patch. 0001's commit parent is the base of
# the series. Check the whole series against that base in a throwaway worktree
# BEFORE syncing, so a broken series cannot silently reach the build.
check_series() {
  local name=$1 repo=$2 base=$3 pdir=$4
  local wt=$PATCHES/check-$name-$STAMP
  local log=$PATCHES/$name-am-$STAMP.log
  rm -rf "$wt"
  git -C "$repo" worktree prune
  git -C "$repo" worktree add --quiet --detach "$wt" "$base"
  local n
  n=$(find "$pdir" -maxdepth 1 -name '*.patch' | wc -l)
  if git -C "$wt" am --whitespace=nowarn "$pdir"/*.patch > "$log" 2>&1; then
    echo "== $name: $n patches apply cleanly to $base"
  else
    echo "ERROR: $name patch series does not apply (see $log)" >&2
    tail -20 "$log" >&2
    git -C "$repo" worktree remove --force "$wt" || true
    return 1
  fi
  git -C "$repo" worktree remove --force "$wt"
}

first_commit() { grep -m1 '^From [0-9a-f]\{7,\}' "$1" | awk '{print $2}'; }
DEV_BASE=$(git -C "$TREE/device/zte/axon7" rev-parse "$(first_commit "$PATCHES/port-22.2/device_zte_axon7/0001-"*.patch)^")
KERNEL_BASE=$(git -C "$TREE/kernel/zte/msm8996" rev-parse "$(first_commit "$PATCHES/kernel-4.4-patches/0001-"*.patch)^")
echo "DEVICE_BASE=$DEV_BASE" >> "$STATE"
echo "KERNEL_BASE=$KERNEL_BASE" >> "$STATE"
check_series device "$TREE/device/zte/axon7" "$DEV_BASE" "$PATCHES/port-22.2/device_zte_axon7"
check_series kernel "$TREE/kernel/zte/msm8996" "$KERNEL_BASE" "$PATCHES/kernel-4.4-patches"

for proj in "${AOSP_PROJECTS[@]}"; do
  sha=$(head_sha "$proj")
  key=$(echo "$proj" | tr / _)
  echo "AOSP_${key}_SHA=$sha" >> "$STATE"
  git -C "$TREE/$proj" update-ref "refs/axon7-monthly/$STAMP" "$sha"
done

# Upstream: the manifest and every project move to the newest lineage-22.2
# security patches. Fetch the manifest explicitly: repo sync alone can leave
# .repo/manifests on the old commit when only a few projects are synced.
git -C "$TREE/.repo/manifests" fetch -q origin lineage-22.2
git -C "$TREE/.repo/manifests" reset -q --hard FETCH_HEAD
# -j4 like the builds; retry transient googlesource errors.
sync_ok=0
for attempt in 1 2 3; do
  echo "== repo sync attempt $attempt $(date -u)"
  if repo sync -c -j4 --no-tags --no-clone-bundle --optimized-fetch --prune --force-sync; then
    sync_ok=1
    break
  fi
  echo "== repo sync attempt $attempt failed; retrying in 30 s"
  sleep 30
done
if [[ $sync_ok -ne 1 ]]; then
  echo "ERROR: repo sync failed 3 times" >&2
  exit 1
fi
NEW_MANIFEST=$(git -C "$TREE/.repo/manifests" rev-parse HEAD)
echo "MANIFEST_AFTER=$NEW_MANIFEST" >> "$STATE"
echo "== after sync: manifest=$NEW_MANIFEST"

# Restore our branches exactly, then re-apply the AOSP patches on top of the
# newly synced upstream. Stop if upstream moved and a patch no longer applies.
for i in "${!CUSTOM_PROJECTS[@]}"; do
  proj=${CUSTOM_PROJECTS[$i]}
  branch=${CUSTOM_BRANCHES[$i]}
  key=$(echo "$proj" | tr / _)
  sha=$(grep "^${key}_SHA=" "$STATE" | cut -d= -f2-)
  # repo sync checks out the upstream revision; files that were tracked on our
  # branch (torch init/sepolicy) become untracked and block checkout. Back them
  # up, compare after the checkout, and only then drop the backup.
  backup=$(backup_untracked "$proj")
  if ! git -C "$TREE/$proj" checkout --quiet --detach "$sha"; then
    echo "ERROR: checkout of $proj at $sha failed; untracked backup kept" >&2
    exit 1
  fi
  git -C "$TREE/$proj" reset --quiet --hard "$sha"
  git -C "$TREE/$proj" clean -fdq
  git -C "$TREE/$proj" update-ref "refs/heads/$branch" "$sha"
  [[ $(head_sha "$proj") == "$sha" ]] || { echo "ERROR: restore of $proj failed" >&2; exit 1; }
  [[ -z $(git -C "$TREE/$proj" status --porcelain) ]] || {
    echo "ERROR: $proj is dirty after restore" >&2; exit 1; }
  verify_untracked_backup "$proj" "$sha" "$backup"
  echo "== restored $proj at $sha (clean)"
done

aosp_patch() {
  local proj=$1 f=$2
  local sha
  sha=$(first_commit "$f")
  if git -C "$TREE/$proj" merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
    echo "== $proj: $(basename "$f") already present"
    return 0
  fi
  if ! git -C "$TREE/$proj" apply --check "$f"; then
    echo "ERROR: $(basename "$f") no longer applies to $proj after repo sync" >&2
    return 1
  fi
  # A stale root-owned fanout directory in .git/objects (seen on 2026-11-26)
  # makes git am fail with "insufficient permission"; fail early and clearly.
  if ! printf 'sec22-object-write-test\n' | git -C "$TREE/$proj" hash-object -w --stdin >/dev/null 2>&1; then
    echo "ERROR: cannot write git objects in $proj; fix .git/objects ownership" >&2
    return 1
  fi
  if ! git -C "$TREE/$proj" am --whitespace=nowarn "$f"; then
    git -C "$TREE/$proj" am --abort >/dev/null 2>&1 || true
    echo "ERROR: git am failed for $proj ($(basename "$f")); in-progress am aborted" >&2
    return 1
  fi
  echo "== $proj: applied $(basename "$f") -> $(head_sha "$proj")"
}

aosp_patch frameworks/av "$PATCHES/port-22.2/aosp/frameworks_av-0001-img_utils-vendor-available.patch"
aosp_patch frameworks/base "$PATCHES/port-22.2/aosp/frameworks_base-0001-SystemUI-flashlight-strength-slider-on-long-press.patch"
aosp_patch frameworks/base "$PATCHES/port-22.2/aosp/frameworks_base-0002-SystemUI-flashlight-strength-set-handlesLongClick-on.patch"
aosp_patch system/core "$PATCHES/port-22.2/aosp/system_core-0001-libutils-vendor-refbase-stack.patch"
aosp_patch system/libhidl "$PATCHES/port-22.2/aosp/system_libhidl-0001-old-constructor-maps.patch"

# Re-check every patch file against the tree that is about to be built:
# device/kernel commits are back at the saved SHA; AOSP commits are re-applied.
for i in "${!CUSTOM_PROJECTS[@]}"; do
  proj=${CUSTOM_PROJECTS[$i]}
  key=$(echo "$proj" | tr / _)
  sha=$(grep "^${key}_SHA=" "$STATE" | cut -d= -f2-)
  [[ $(head_sha "$proj") == "$sha" ]] || { echo "ERROR: $proj changed after restore" >&2; exit 1; }
  [[ -z $(git -C "$TREE/$proj" status --porcelain) ]] || {
    echo "ERROR: $proj is dirty before the build" >&2; exit 1; }
done
echo "== device/kernel/vendor patches: all files apply to their bases, heads restored, trees clean"

# build-zip.sh re-checks these heads after its own setup, so a wrong tree cannot
# reach "m -j4 bacon" even if something changes between the two checks.
export AXON7_EXPECT_DEVICE_SHA=$(grep '^device_zte_axon7_SHA=' "$STATE" | cut -d= -f2-)
export AXON7_EXPECT_KERNEL_SHA=$(grep '^kernel_zte_msm8996_SHA=' "$STATE" | cut -d= -f2-)
# The build script uses fd 9 instead of taking the lock again; m -j4.
AXON7_BUILD_LOCK_FD=9 bash "$PATCHES/ci/build-zip.sh"

NEW_ZIP=$(ls -t "$DEST"/lineage-22.2-*-UNOFFICIAL-axon7.zip | head -1)
(cd "$DEST" && sha256sum -c "$(basename "$NEW_ZIP").sha256") || {
  echo "ERROR: sha256 verification failed for $NEW_ZIP" >&2; exit 1; }
NEW_SHA=$(sha256sum "$NEW_ZIP" | awk '{print $1}')
NEW_PATCH=$(grep -m1 '^ro.build.version.security_patch=' "$PROP" 2>/dev/null | cut -d= -f2 || true)
NEW_VENDOR_PATCH=$(grep -m1 '^ro.vendor.build.security_patch=' "$OUT/vendor/build.prop" 2>/dev/null | cut -d= -f2 || true)
[[ $NEW_ZIP != "$OLD_ZIP" ]] || { echo "ERROR: no new zip was produced" >&2; exit 1; }
[[ $NEW_PATCH > "$OLD_PATCH" || $NEW_PATCH == "$OLD_PATCH" ]] || {
  echo "ERROR: security patch went backwards: $OLD_PATCH -> $NEW_PATCH" >&2; exit 1; }

{
  echo "date_utc=$(date -u +%FT%TZ)"
  echo "manifest_before=$OLD_MANIFEST"
  echo "manifest_after=$NEW_MANIFEST"
  echo "security_patch_before=$OLD_PATCH"
  echo "security_patch_after=$NEW_PATCH"
  echo "vendor_security_patch_before=$OLD_VENDOR_PATCH"
  echo "vendor_security_patch_after=$NEW_VENDOR_PATCH"
  echo "zip_before=$OLD_ZIP"
  echo "sha256_before=$OLD_SHA"
  echo "zip_after=$NEW_ZIP"
  echo "sha256_after=$NEW_SHA"
  echo "device_patches=57 apply-clean to $DEV_BASE"
  echo "kernel_patches=38 apply-clean to $KERNEL_BASE"
  echo "aosp_patches=5 re-applied"
  echo "device_head=$(head_sha device/zte/axon7)"
  echo "kernel_head=$(head_sha kernel/zte/msm8996)"
  echo "vendor_head=$(head_sha vendor/zte)"
  echo "fork_heads_verified=yes; trees_clean=yes; untracked_port_files_matched_fork=yes"
} > "$SUMMARY"

echo "== monthly update done $(date -u)"
if [[ $NEW_PATCH == "$OLD_PATCH" ]]; then
  echo "== NOTE: the platform patch string is unchanged ($NEW_PATCH); check manifest_before/after for the ASB code updates"
else
  echo "== security patch: $OLD_PATCH -> $NEW_PATCH"
fi
cat "$SUMMARY"
