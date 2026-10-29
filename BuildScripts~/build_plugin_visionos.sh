#!/bin/bash -eu

# Builds the native plugin for visionOS device and Simulator into Runtime/Plugins/visionOS/webrtc.xcframework.
# Usage: build_plugin_visionos.sh <path to webrtc-visionos.zip from build_libwebrtc_visionos.sh>

LIBWEBRTC_ZIP=$(cd $(dirname $1); pwd)/$(basename $1)
export SOLUTION_DIR=$(pwd)/Plugin~
export WEBRTC_FRAMEWORK_DIR=$(pwd)/Runtime/Plugins/visionOS
export BUILD_DIR=$(pwd)/build/visionos

rm -rf "$BUILD_DIR" "$SOLUTION_DIR/webrtc"
mkdir -p "$BUILD_DIR"
unzip -q -d "$BUILD_DIR/libwebrtc" "$LIBWEBRTC_ZIP"

cd "$SOLUTION_DIR"
for sdk in "xros" "xrsimulator"
do
  # FindWebRTC.cmake reads Plugin~/webrtc and wants a debug library too; this builds release only.
  rm -rf webrtc && mkdir -p webrtc/lib
  ln -s "$BUILD_DIR/libwebrtc/include" webrtc/include
  cp "$BUILD_DIR/libwebrtc/lib/$sdk/libwebrtc.a" webrtc/lib/libwebrtc.a
  ln -s libwebrtc.a webrtc/lib/libwebrtcd.a

  # CMAKE_POLICY_VERSION_MINIMUM: CMake 4 refuses googletest's old cmake_minimum_required.
  cmake . \
    -G Xcode \
    -D CMAKE_SYSTEM_NAME=visionOS \
    -D CMAKE_OSX_SYSROOT=$sdk \
    -D CMAKE_OSX_ARCHITECTURES=arm64 \
    -D CMAKE_OSX_DEPLOYMENT_TARGET=2.0 \
    -D CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -B "$BUILD_DIR/$sdk"

  xcodebuild \
    -sdk $sdk \
    -project "$BUILD_DIR/$sdk/webrtc.xcodeproj" \
    -target WebRTCPlugin \
    -configuration Release \
    CODE_SIGNING_ALLOWED=NO

  mv "$WEBRTC_FRAMEWORK_DIR/webrtc.framework" "$BUILD_DIR/$sdk/webrtc.framework"
done
rm -rf webrtc

rm -rf "$WEBRTC_FRAMEWORK_DIR/webrtc.xcframework"
xcodebuild -create-xcframework \
  -framework "$BUILD_DIR/xros/webrtc.framework" \
  -framework "$BUILD_DIR/xrsimulator/webrtc.framework" \
  -output "$WEBRTC_FRAMEWORK_DIR/webrtc.xcframework"
