#!/bin/bash -eu

# Builds libwebrtc (M116) for visionOS device and Simulator, arm64, release.
# Output: artifacts/webrtc-visionos.zip with lib/xros/libwebrtc.a, lib/xrsimulator/libwebrtc.a, include, LICENSE.md.
# Needs Xcode 26 with the visionOS platform, and a python3 that can install setuptools.

if [ ! -e "$(pwd)/depot_tools" ]
then
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi

export COMMAND_DIR=$(cd $(dirname $0); pwd)
export WEBRTC_VERSION=5845
export OUTPUT_DIR="$(pwd)/out"
export ARTIFACTS_DIR="$(pwd)/artifacts"

# Chromium's hooks import pkg_resources, which Python 3.12+ no longer ships.
if [ ! -e "$(pwd)/venv" ]
then
  python3 -m venv venv
  venv/bin/pip install -q "setuptools<81"
fi
export PYTHONPATH="$(echo $(pwd)/venv/lib/python3*/site-packages)"
printf "../venv/bin" > depot_tools/python3_bin_reldir.txt
export PATH="$(pwd)/venv/bin:$(pwd)/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=0

if [ ! -e "$(pwd)/src" ]
then
  cat > .gclient <<EOF
solutions = [{"name": "src", "url": "https://webrtc.googlesource.com/src.git@refs/branch-heads/$WEBRTC_VERSION",
              "deps_file": "DEPS", "managed": False, "custom_deps": {}}]
target_os = ["ios", "mac"]
EOF
  gclient sync --no-history --nohooks --with_branch_heads
  gclient runhooks

  # The iOS patches, as in build_libwebrtc_ios.sh
  patch -N "src/BUILD.gn" < "$COMMAND_DIR/patches/add_jsoncpp.patch"
  patch -N "src/api/task_queue/BUILD.gn" < "$COMMAND_DIR/patches/disable_task_queue_gcd.patch"
  patch -N "src/sdk/BUILD.gn" < "$COMMAND_DIR/patches/add_objc_deps.patch"
  patch -N "src/modules/video_coding/codecs/vp8/libvpx_vp8_encoder.cc" < "$COMMAND_DIR/patches/libvpx_vp8_encoder.patch"

  # visionOS
  patch -N -p1 -d src < "$COMMAND_DIR/patches/visionos_build.patch"
  patch -N -p1 -d src < "$COMMAND_DIR/patches/visionos_sdk.patch"
  patch -N -p1 -d src < "$COMMAND_DIR/patches/visionos_zlib.patch"
fi

# Xcode's clang (Chromium's clang 17 cannot target xros) with Chromium's llvm-ar and other tools,
# which Xcode lacks. Wrappers, not symlinks: clang finds its resource headers relative to argv[0].
TOOLCHAIN_DIR="$(pwd)/xcode-toolchain"
rm -rf "$TOOLCHAIN_DIR" && mkdir -p "$TOOLCHAIN_DIR/bin"
for tool in "$(pwd)"/src/third_party/llvm-build/Release+Asserts/bin/*; do ln -s "$tool" "$TOOLCHAIN_DIR/bin/"; done
for cc in clang clang++; do
  rm "$TOOLCHAIN_DIR/bin/$cc"
  printf '#!/bin/sh\nexec %s "$@"\n' "$(xcrun -f $cc)" > "$TOOLCHAIN_DIR/bin/$cc"
  chmod +x "$TOOLCHAIN_DIR/bin/$cc"
done

mkdir -p "$ARTIFACTS_DIR/lib"

for target_environment in "device" "simulator"
do
  sdk="xros"
  if [ $target_environment = "simulator" ]; then
    sdk="xrsimulator"
  fi

  gn gen "$OUTPUT_DIR/$sdk" --root="src" \
    --args="is_debug=false \
    target_os=\"ios\" \
    target_cpu=\"arm64\" \
    target_platform=\"visionos\" \
    target_environment=\"${target_environment}\" \
    ios_deployment_target=\"2.0\" \
    clang_base_path=\"$TOOLCHAIN_DIR\" \
    clang_use_chrome_plugins=false \
    use_lld=false \
    rtc_use_h264=false \
    use_custom_libcxx=false \
    treat_warnings_as_errors=false \
    ios_enable_code_signing=false \
    rtc_include_tests=false \
    rtc_build_examples=false \
    use_cxx17=true"

  ninja -C "$OUTPUT_DIR/$sdk" webrtc

  mkdir -p "$ARTIFACTS_DIR/lib/$sdk"
  cp "$OUTPUT_DIR/$sdk/obj/libwebrtc.a" "$ARTIFACTS_DIR/lib/$sdk/"
done

python3 "./src/tools_webrtc/libs/generate_licenses.py" \
  --target :webrtc "$OUTPUT_DIR/xros" "$OUTPUT_DIR/xros"

cd src
find . -name "*.h" -print | cpio -pd "$ARTIFACTS_DIR/include"

cp "$OUTPUT_DIR/xros/LICENSE.md" "$ARTIFACTS_DIR"

cd "$ARTIFACTS_DIR"
zip -r webrtc-visionos.zip lib include LICENSE.md
