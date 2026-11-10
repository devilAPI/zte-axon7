#!/bin/bash
# Mesa freedreno (Adreno 530: GL ES via gallium; turnip has no a5xx) for
# Android 17 arm64, built out of tree with the NDK and meson as Mesa's
# docs/android.rst describes, installed as vendor prebuilts for the axon7m
# device tree (milestone M1b, PLAN.md).
#
# Run on the build server as user build (tmux los24mesa):
#   /srv/los24/axon7/repo/lineageos-24-mainline/scripts/mesa-build.sh [setup|build|all]
# Layout:
#   /srv/los24/tools/android-ndk-r30   NDK (downloaded, sha1 checked)
#   /srv/los24/tools/pylib, meson      meson, mako, pyyaml (wheels from PyPI, no pip)
#   /srv/los24/mesa/src                Mesa $MESA_TAG (shallow)
#   /srv/los24/mesa/build-android      meson build dir
#   /srv/los24/mesa/out                staged libs (lib64/egl/...) for the device tree
# Log: /srv/los24/logs/mesa-build.log (when started as below)
# Time: setup ~10 min (downloads), build ~10-20 min.
set -euo pipefail
MESA_TAG=${MESA_TAG:-mesa-26.2.6}
NDK_VER=r30
NDK_SHA1=5107f898313790e449e87eee2183d9a20602dee9	# developer.android.com/ndk/downloads, linux zip
API=${API:-35}
TOOLS=/srv/los24/tools
NDK=$TOOLS/android-ndk-$NDK_VER
M=/srv/los24/mesa
mkdir -p "$TOOLS" "$M"

setup() {
	if [ ! -x "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]; then
		z=$TOOLS/android-ndk-$NDK_VER-linux.zip
		[ -f "$z" ] || curl -fL -o "$z" "https://dl.google.com/android/repository/android-ndk-$NDK_VER-linux.zip"
		echo "$NDK_SHA1  $z" | sha1sum -c -
		(cd "$TOOLS" && unzip -q "$z") && rm -f "$z"
	fi
	# meson, mako, pyyaml: pure-Python wheels unpacked into $TOOLS/pylib (the
	# server has no pip/venv, and nothing gets installed system-wide)
	if [ ! -f "$TOOLS/pylib/mesonbuild/__init__.py" ]; then
		mkdir -p "$TOOLS/pylib" "$TOOLS/wheels"
		for pkg in meson mako pyyaml markupsafe; do
			url=$(curl -fsSL "https://pypi.org/pypi/$pkg/json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ws = [u for u in d["urls"] if u["packagetype"] == "bdist_wheel"]
# pure-Python wheel if there is one, else the cp313 manylinux x86_64 one
pick = [u for u in ws if u["filename"].endswith("-none-any.whl")] or \
       [u for u in ws if "cp313-cp313-manylinux" in u["filename"] and "x86_64" in u["filename"]]
print(pick[0]["url"] if pick else "")')
			[ -n "$url" ] || { echo "no wheel for $pkg"; exit 1; }
			curl -fsSL -o "$TOOLS/wheels/${url##*/}" "$url"
			(cd "$TOOLS/pylib" && unzip -qo "$TOOLS/wheels/${url##*/}")
		done
		# a real script file: meson re-runs itself through sys.argv[0]
		printf '#!/usr/bin/env python3\nimport sys\nsys.path.insert(0, "%s")\nfrom mesonbuild.mesonmain import main\nsys.exit(main())\n' "$TOOLS/pylib" > "$TOOLS/meson"
		chmod +x "$TOOLS/meson"
	fi
	if [ ! -d "$M/src/.git" ]; then
		git clone -q --depth 1 -b "$MESA_TAG" https://gitlab.freedesktop.org/mesa/mesa.git "$M/src"
	fi
	B=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
	cat > "$M/android-aarch64.ini" <<EOF
[binaries]
ar = '$B/llvm-ar'
c = ['$B/aarch64-linux-android$API-clang']
cpp = ['$B/aarch64-linux-android$API-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$B/llvm-strip'
pkg-config = ['/bin/false']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF
}

build() {
	export PATH=$TOOLS:/srv/los24/lineage-24.0/prebuilts/build-tools/linux-x86/bin:$PATH
	export PYTHONPATH=$TOOLS/pylib
	rm -rf "$M/build-android"
	# freedreno gallium (GL ES 3.x for a5xx) + EGL for Android; no Vulkan
	# (turnip starts at a6xx), no LLVM, libdrm from meson's wrap fallback.
	meson setup "$M/build-android" "$M/src" --cross-file "$M/android-aarch64.ini" \
		-Dbuildtype=release -Dstrip=true \
		-Dplatforms=android -Dplatform-sdk-version=$API -Dandroid-stub=true \
		-Dandroid-libbacktrace=disabled \
		-Dgallium-drivers=freedreno -Dvulkan-drivers= -Dfreedreno-kmds=msm \
		-Degl=enabled -Dgles1=disabled -Dgles2=enabled -Dopengl=true \
		-Degl-lib-suffix=_mesa -Dgles-lib-suffix=_mesa \
		-Dglx=disabled -Dgbm=disabled -Dllvm=disabled -Dshared-llvm=disabled \
		-Dzstd=disabled -Dexpat=disabled -Dvalgrind=disabled -Dlibunwind=disabled \
		-Dallow-fallback-for=libdrm -Dtools=
	meson compile -C "$M/build-android"
	rm -rf "$M/out" "$M/out-root"; DESTDIR=$M/out-root meson install -C "$M/build-android" --no-rebuild >/dev/null
	# Android's EGL loader opens /vendor/lib64/egl/lib{EGL,GLESv2}_mesa.so
	# (ro.hardware.egl=mesa); the gallium megadriver goes to /vendor/lib64.
	mkdir -p "$M/out/lib64/egl"
	find "$M/out-root" \( -name 'libEGL_mesa.so*' -o -name 'libGLES*_mesa.so*' \) -exec cp -a {} "$M/out/lib64/egl/" \;
	find "$M/out-root" -name '*.so*' ! -name 'libEGL_mesa.so*' ! -name 'libGLES*_mesa.so*' -exec cp -a {} "$M/out/lib64/" \;
	ls -laR "$M/out"
	echo "mesa $MESA_TAG ndk $NDK_VER api $API $(date -u +%FT%TZ)" > "$M/out/version"
}

case "${1:-all}" in
	setup) setup ;;
	build) build ;;
	all) setup; build ;;
	*) echo "usage: $0 [setup|build|all]" >&2; exit 2 ;;
esac
