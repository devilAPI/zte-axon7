#!/bin/bash
# Upstream libcamera (simple pipeline + software ISP) and its Android camera
# HAL for Android 17 arm64, built out of tree with the NDK and meson like
# Mesa (scripts/mesa-build.sh), installed as vendor prebuilts
# (device/zte/axon7m-libcamera). AOSP's external/libcamera is ChromeOS' fork
# without the software ISP, so CAMSS (no hardware ISP on mainline) only
# gives raw Bayer there.
#
# Run on the build server as user build:
#   /srv/los24/axon7/repo/lineageos-24-mainline/scripts/libcamera-build.sh [setup|build|all]
# Layout:
#   /srv/los24/tools                   NDK, meson (mesa-build.sh setup)
#   /srv/los24/libcamera/src           libcamera $LC_REF (shallow)
#   /srv/los24/libcamera/build-android meson build dir
#   /srv/los24/libcamera/out           staged libs for the device tree
set -euo pipefail
LC_REF=${LC_REF:-master}
API=${API:-35}
TOOLS=/srv/los24/tools
NDK=$TOOLS/android-ndk-r30
L=/srv/los24/libcamera
B=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
mkdir -p "$L"

setup() {
	[ -x "$B/clang" ] || { echo "no NDK: run mesa-build.sh setup first"; exit 1; }
	# Python modules libcamera's build needs besides pyyaml (from Mesa's setup)
	for pkg in jinja2 ply; do
		python3 -c "import sys; sys.path.insert(0, '$TOOLS/pylib'); import $pkg" 2>/dev/null && continue
		url=$(curl -fsSL "https://pypi.org/pypi/$pkg/json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ws = [u for u in d["urls"] if u["packagetype"] == "bdist_wheel" and u["filename"].endswith("-none-any.whl")]
print(ws[0]["url"] if ws else "")')
		[ -n "$url" ] || { echo "no wheel for $pkg"; exit 1; }
		curl -fsSL -o "$TOOLS/wheels/${url##*/}" "$url"
		(cd "$TOOLS/pylib" && unzip -qo "$TOOLS/wheels/${url##*/}")
	done
	if [ ! -d "$L/src/.git" ]; then
		git clone -q --depth 1 -b "$LC_REF" https://git.libcamera.org/libcamera/libcamera.git "$L/src"
	fi
	cat > "$L/android-aarch64.ini" <<EOF
[binaries]
ar = '$B/llvm-ar'
c = ['$B/aarch64-linux-android$API-clang']
cpp = ['$B/aarch64-linux-android$API-clang++', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$B/llvm-strip'
pkg-config = ['/bin/false']
cmake = '/srv/los24/lineage-24.0/prebuilts/cmake/linux-x86/bin/cmake'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'

[built-in options]
c_link_args = ['-lm']
cpp_link_args = ['-lm']

[cmake]
CMAKE_ANDROID_NDK = '$NDK'
CMAKE_ANDROID_ARCH_ABI = 'arm64-v8a'
CMAKE_SYSTEM_VERSION = '$API'
EOF
	# libjpeg and libexif for the HAL from meson's wrap database
	mkdir -p "$L/src/subprojects"
	export PATH=$TOOLS:$PATH PYTHONPATH=$TOOLS/pylib
	(cd "$L/src" && { [ -f subprojects/libjpeg-turbo.wrap ] || meson wrap install libjpeg-turbo; }
		[ -f subprojects/libexif.wrap ] || meson wrap install libexif) || true
}

build() {
	local p
	git -c safe.directory='*' -C "$L/src" checkout -q -- .
	for p in "${AXON7_REPO:-/srv/los24/axon7/repo}"/lineageos-24-mainline/libcamera/patches/*.patch; do
		[ -e "$p" ] || continue
		git -c safe.directory='*' -C "$L/src" apply "$p"
		echo "libcamera patch applied: ${p##*/}"
	done
	export PATH=$TOOLS:/srv/los24/lineage-24.0/prebuilts/build-tools/linux-x86/bin:/srv/los24/lineage-24.0/prebuilts/cmake/linux-x86/bin:$PATH
	export PYTHONPATH=$TOOLS/pylib
	rm -rf "$L/build-android"
	meson setup "$L/build-android" "$L/src" --cross-file "$L/android-aarch64.ini" \
		-Dbuildtype=release -Dstrip=true \
		--prefix=/vendor --libdir=lib64 --libexecdir=bin --datadir=etc --sysconfdir=etc \
		-Dandroid=enabled -Dandroid_platform=generic \
		-Dpipelines=simple -Dipas=softisp -Dsoftisp-gpu=disabled \
		-Dcam=disabled -Dqcam=disabled -Dgstreamer=disabled -Dv4l2=false \
		-Dlc-compliance=disabled -Dtest=false -Ddocumentation=disabled \
		-Dpycamera=disabled -Dudev=disabled -Dtracing=disabled \
		-Dlibunwind=disabled -Dlibdw=disabled \
		--force-fallback-for=libyaml,libjpeg,libexif \
		-Dwerror=false -Dlibjpeg-turbo:default_library=static -Dlibexif:default_library=static -Dlibyaml:default_library=static -Dlibjpeg-turbo:werror=false -Dlibexif:werror=false -Dlibyaml:werror=false
	meson compile -C "$L/build-android"
	rm -rf "$L/out" "$L/out-root"; DESTDIR=$L/out-root meson install -C "$L/build-android" --no-rebuild >/dev/null
	mkdir -p "$L/out"
	cp -a "$L/out-root/vendor/." "$L/out/"
	find "$L/out" -type f | sort
	echo "libcamera $(git -c safe.directory='*' -C "$L/src" log -1 --format=%h) ndk r30 api $API $(date -u +%FT%TZ)" > "$L/out/version"
}

case "${1:-all}" in
	setup) setup ;;
	build) build ;;
	all) setup; build ;;
	*) echo "usage: $0 [setup|build|all]" >&2; exit 2 ;;
esac
