#!/bin/bash
# Build the Axon 7 mainline kernel for LineageOS 24 on the build server.
#
#   Kernel tree:  /srv/los24/kernel/linux   (linux-stable v7.3.1, shallow, branch
#                 axon7-android = v7.3.1 + Nura's patch series + our Android patches)
#   Output:       /srv/los24/kernel/out     (O= build dir)
#   Staged for the Android build: /srv/los24/kernel/prebuilt/
#                 Image (raw: the multi-boot shim does not gunzip), dtb/,
#                 modules/*.ko + modules.load*, config, System.map, version
#
# Usage (as user build):  kernel-build.sh [setup|config|build|stage|all]...   (default all)
#   setup   apply missing patches (Nura series from AXON7_REPO, then ours)
#   config  Nura config + kernel/android-axon7m.config -> out/.config
#   build   Image, dtbs, modules
#   stage   copy the results to prebuilt/
#
# Environment:
#   AXON7_REPO  copy of the zte-axon7 repository (default /srv/los24/axon7/repo)
#   J           make jobs (default 7)
# Note: never chown -R the kernel tree: git then re-hashes every file
# (an hour on the server's busy HDD).
# Time: a full build from scratch takes about 25-35 min on the 7-thread server,
# a rebuild after a driver change 1-3 min.
set -euo pipefail
KSRC=/srv/los24/kernel/linux
KOUT=/srv/los24/kernel/out
KPRE=/srv/los24/kernel/prebuilt
REPO=${AXON7_REPO:-/srv/los24/axon7/repo}
NURA=$REPO/postmarketos/pmaports-local/device/testing/linux-zte-axon7
OURS=$REPO/lineageos-24-mainline/kernel
J=${J:-7}

# Toolchain: LineageOS 24's prebuilt clang once synced, else 22.2's (clang 19).
pick_clang() {
	local d
	for d in /srv/los24/lineage-24.0/prebuilts/clang/host/linux-x86/clang-r5* \
		 /srv/aosp/lineage-22.2/prebuilts/clang/host/linux-x86/clang-r536225; do
		[ -x "$d/bin/clang" ] && CL=$d
	done
	[ -n "${CL:-}" ] || { echo "no prebuilt clang found" >&2; exit 1; }
	T=$(dirname "$(dirname "$(dirname "$(dirname "$(dirname "$CL")")")")")
	BT=$T/prebuilts/build-tools
	export PATH=$CL/bin:$BT/linux-x86/bin:$PATH
	export LD_LIBRARY_PATH=$CL/lib64:$CL/lib:${LD_LIBRARY_PATH:-}
}

kmake() {
	# LOCALVERSION= : no "+" from setlocalversion (the tree is not at a tag)
	make -C "$KSRC" O="$KOUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 LOCALVERSION= \
		HOSTCFLAGS="-I/usr/include -I/usr/include/x86_64-linux-gnu" \
		HOSTLDFLAGS="-L/usr/lib/x86_64-linux-gnu -fuse-ld=lld" \
		-j"$J" "$@"
}

setup() {
	cd "$KSRC"
	git config user.name >/dev/null || git config user.name build
	git config user.email >/dev/null || git config user.email build@compiler
	# Nura series: applied when its subject line is not in the log yet
	local p s
	for p in "$NURA"/00*.patch; do
		[ -e "$p" ] || continue
		# subject as git am would record it (folded Subject: lines joined)
		s=$(git mailinfo /dev/null /dev/null < "$p" | sed -n 's/^Subject: //p')
		# no grep -q: with pipefail, git log would die of SIGPIPE and "fail"
		if git log --format=%s | grep -xF -- "$s" >/dev/null; then continue; fi
		echo "apply $(basename "$p")"
		git am -q --whitespace=nowarn "$p"
	done
	git log --oneline v7.3.1..HEAD 2>/dev/null | wc -l | sed 's/^/commits on top of 7.3.1: /' || true
	# our own patches: plain patch(1), checked by a reverse dry run. git am
	# would refresh the index first, which re-hashes the whole tree on the
	# server's busy HDD (an hour); these patches are not git commits here.
	for p in "$OURS"/patches/*.patch; do
		[ -e "$p" ] || continue
		if patch -d "$KSRC" -p1 -R -s -f --dry-run < "$p" >/dev/null 2>&1; then
			echo "already applied: $(basename "$p")"
		else
			patch -d "$KSRC" -p1 -N -s < "$p"
			echo "applied: $(basename "$p")"
		fi
	done
}

config() {
	mkdir -p "$KOUT"
	cp "$NURA/config-zte-axon7.aarch64" "$KOUT/.config"
	(cd "$KSRC" && KCONFIG_CONFIG="$KOUT/.config" ARCH=arm64 LLVM=1 \
		scripts/kconfig/merge_config.sh -m -O "$KOUT" "$KOUT/.config" "$OURS/android-axon7m.config" >/dev/null)
	kmake olddefconfig >/dev/null
	"$REPO/lineageos-24-mainline/scripts/kernel-config-check.sh" "$KOUT/.config" "$OURS/android-axon7m.config"
}

build() {
	# only our DTB: "dtbs" would build every qcom (and other enabled ARCH_*) board
	kmake Image qcom/msm8996-zte-axon7.dtb modules
	local isz
	isz=$(od -An -t u8 -j 16 -N 8 "$KOUT/arch/arm64/boot/Image" | tr -d ' ')
	echo "Image image_size: $((isz / 1048576)) MiB (limit about 48 MiB below the splash)"
	[ "$isz" -lt $((48 * 1048576)) ] || { echo "Image too large for the shim's 0x80000000..0x83400000 window" >&2; exit 1; }
}

stage() {
	rm -rf "$KPRE.new"
	mkdir -p "$KPRE.new/dtb" "$KPRE.new/modules"
	cp "$KOUT/arch/arm64/boot/Image" "$KOUT/System.map" "$KPRE.new/"
	cp "$KOUT/.config" "$KPRE.new/config"
	cp "$KOUT/arch/arm64/boot/dts/qcom/msm8996-zte-axon7.dtb" "$KPRE.new/dtb/"
	kmake INSTALL_MOD_PATH="$KPRE.new/mod-install" INSTALL_MOD_STRIP=1 modules_install >/dev/null
	find "$KPRE.new/mod-install" -name '*.ko' -exec cp {} "$KPRE.new/modules/" \;
	local kr
	kr=$(cat "$KOUT/include/config/kernel.release")
	cp "$KPRE.new/mod-install/lib/modules/$kr/modules.order" "$KPRE.new/modules/" 2>/dev/null || true
	rm -rf "$KPRE.new/mod-install"
	local own
	own=$(cd "$OURS/patches" 2>/dev/null && ls *.patch 2>/dev/null | cut -c1-4 | tr '\n' ' ')
	echo "$kr $(git -C "$KSRC" rev-parse --short HEAD) +patches ${own:-none}$(date -u +%FT%TZ)" > "$KPRE.new/version"
	rm -rf "$KPRE.old"; [ -d "$KPRE" ] && mv "$KPRE" "$KPRE.old"; mv "$KPRE.new" "$KPRE"
	echo "staged $(cat "$KPRE/version"): $(ls "$KPRE/modules" | grep -c '\.ko$') modules in $KPRE"
}

pick_clang
echo "== $(date -u +%FT%TZ) kernel-build.sh ${*:-all}, clang $CL"
for step in "${@:-all}"; do
	case "$step" in
	setup) setup ;;
	config) config ;;
	build) build ;;
	stage) stage ;;
	all) setup; config; build; stage ;;
	*) echo "usage: $0 [setup|config|build|stage|all]..." >&2; exit 2 ;;
	esac
done
