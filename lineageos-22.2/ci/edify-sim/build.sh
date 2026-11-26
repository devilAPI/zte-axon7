#!/bin/bash
# Build edify_sim against the host libedify of an AOSP tree that has been built
# (out/soong/.intermediates/.../libedify). Usage: build.sh TREE OUT
set -eu
tree=${1:?tree}; out=${2:?output binary}
here=$(cd "$(dirname "$0")" && pwd)
clang=$(ls -d "$tree"/prebuilts/clang/host/linux-x86/clang-r*/ | sort | tail -1)
i=$tree/out/soong/.intermediates
libs=("$i"/bootable/deprecated-ota/edify/libedify/linux_glibc_x86_64_static/libedify.a
      "$i"/system/libbase/libbase/linux_glibc_x86_64_static/libbase.a)
"$clang/bin/clang++" -std=c++20 -O1 -stdlib=libc++ -fuse-ld=lld \
	-I"$tree"/bootable/deprecated-ota/edify/include -I"$tree"/system/libbase/include \
	-I"$tree"/bootable/recovery/otautil/include \
	"$here/edify_sim.cpp" "${libs[@]}" -static-libstdc++ -lpthread -o "$out"
