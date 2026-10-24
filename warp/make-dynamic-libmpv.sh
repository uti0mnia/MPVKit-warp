#!/bin/bash
# Warp: links each platform's static libmpv, FFmpeg and every library under
# them into ONE dynamic Libmpv.framework, then dist/dynamic/Libmpv.xcframework.
#
# Why: the LGPL lets a closed app use mpv and FFmpeg when the user can swap
# them for a version they built. With everything static, they sit inside the
# app's own binary; here they sit in a framework of their own that only
# exports mpv's API (`_mpv_*`), and the app links nothing else from them.
#
# Run after `make build platform=ios,isimulator,tvos,tvsimulator,macos`
# (see warp/README.md). Usage: warp/make-dynamic-libmpv.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:-0.41.0}
DIST=dist
OUT=dist/dynamic
rm -rf "$OUT"
mkdir -p "$OUT"

# Link order: mpv first (force-loaded), then what it needs, then what those
# need. The linker pulls only the objects reached from mpv's API.
LIBS=(
  FFmpeg/libavfilter FFmpeg/libavformat FFmpeg/libavcodec FFmpeg/libavdevice
  FFmpeg/libswresample FFmpeg/libswscale FFmpeg/libavutil
  libplacebo/libplacebo libdovi/libdovi lcms2/liblcms2
  libshaderc/libshaderc_combined vulkan/libMoltenVK
  libass/libass libharfbuzz/libharfbuzz libfreetype/libfreetype
  libfribidi/libfribidi libunibreak/libunibreak
  libbluray/libbluray libuchardet/libuchardet
  libdav1d/libdav1d libuavs3d/libuavs3d
  openssl/libssl openssl/libcrypto
  libluajit/libluajit
)

# platform  sdk                 os-version   arches
# arm64 only: the devices are, and so is the Mac that builds and tests Warp
# (simulators and `swift test`). Add x86_64 to a row for an Intel Mac.
PLATFORMS=(
  "ios          iphoneos          ios17.5            arm64"
  "isimulator   iphonesimulator   ios17.5-simulator  arm64"
  "tvos         appletvos         tvos17.5           arm64"
  "tvsimulator  appletvsimulator  tvos17.5-simulator arm64"
  "macos        macosx            macos14.0          arm64"
)

link_slice() {
  local platform=$1 sdk=$2 os=$3 arch=$4 out=$5
  local sysroot thin args=()
  sysroot=$(xcrun --sdk "$sdk" --show-sdk-path)
  thin="$DIST/libmpv/$platform/thin/$arch/lib/libmpv.a"
  [[ -f $thin ]] || { echo "missing $thin: build $platform first" >&2; exit 1; }
  for lib in "${LIBS[@]}"; do
    local path="$DIST/${lib%%/*}/$platform/thin/$arch/lib/${lib##*/}.a"
    [[ -f $path ]] && args+=("$path")
  done
  local frameworks=(Foundation CoreFoundation AVFoundation AudioToolbox CoreAudio CoreMedia CoreVideo
                    VideoToolbox Metal QuartzCore IOSurface CoreGraphics CoreText Security)
  if [[ $platform == macos ]]; then
    frameworks+=(AppKit IOKit Cocoa OpenGL)
  else
    frameworks+=(UIKit OpenGLES)
  fi
  local flags=()
  for f in "${frameworks[@]}"; do flags+=(-framework "$f"); done
  xcrun --sdk "$sdk" clang -dynamiclib \
    -target "$arch-apple-$os" -isysroot "$sysroot" \
    -install_name @rpath/Libmpv.framework/Libmpv \
    -compatibility_version 1 -current_version "$VERSION" \
    -Wl,-force_load,"$thin" "${args[@]}" \
    "${flags[@]}" -lc++ -lz -lbz2 -liconv -lxml2 -lresolv -lexpat \
    -Wl,-exported_symbol,'_mpv_*' -Wl,-dead_strip \
    -o "$out"
}

info_plist() {
  local platform=$1
  local supported minimum
  case $platform in
    ios) supported=iPhoneOS; minimum=17.5 ;;
    isimulator) supported=iPhoneSimulator; minimum=17.5 ;;
    tvos) supported=AppleTVOS; minimum=17.5 ;;
    tvsimulator) supported=AppleTVSimulator; minimum=17.5 ;;
    macos) supported=MacOSX; minimum=14.0 ;;
  esac
  local key=MinimumOSVersion
  [[ $platform == macos ]] && key=LSMinimumSystemVersion
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Libmpv</string>
  <key>CFBundleIdentifier</key><string>com.cmclewin.warp.Libmpv</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Libmpv</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$supported</string></array>
  <key>$key</key><string>$minimum</string>
</dict>
</plist>
PLIST
}

xcargs=()
for row in "${PLATFORMS[@]}"; do
  read -r platform sdk os arches <<<"$row"
  [[ -d $DIST/libmpv/$platform ]] || { echo "skipping $platform (not built)"; continue; }
  slices=()
  for arch in $arches; do
    slice="$OUT/$platform/$arch/Libmpv"
    mkdir -p "$(dirname "$slice")"
    echo "linking $platform $arch"
    link_slice "$platform" "$sdk" "$os" "$arch" "$slice"
    slices+=("$slice")
  done
  fw="$OUT/$platform/Libmpv.framework"
  headers="$DIST/libmpv/$platform/thin/${arches%% *}/include/mpv"
  if [[ $platform == macos ]]; then
    # macOS frameworks are deep bundles.
    mkdir -p "$fw/Versions/A/Headers/mpv" "$fw/Versions/A/Modules" "$fw/Versions/A/Resources"
    lipo -create "${slices[@]}" -output "$fw/Versions/A/Libmpv"
    cp "$headers"/*.h "$fw/Versions/A/Headers/mpv/"
    info_plist "$platform" > "$fw/Versions/A/Resources/Info.plist"
    printf 'framework module Libmpv [system] {\n    umbrella "."\n    export *\n}\n' > "$fw/Versions/A/Modules/module.modulemap"
    ln -s A "$fw/Versions/Current"
    for item in Libmpv Headers Modules Resources; do ln -s "Versions/Current/$item" "$fw/$item"; done
  else
    mkdir -p "$fw/Headers/mpv" "$fw/Modules"
    lipo -create "${slices[@]}" -output "$fw/Libmpv"
    cp "$headers"/*.h "$fw/Headers/mpv/"
    info_plist "$platform" > "$fw/Info.plist"
    printf 'framework module Libmpv [system] {\n    umbrella "."\n    export *\n}\n' > "$fw/Modules/module.modulemap"
  fi
  xcargs+=(-framework "$fw")
done

xcodebuild -create-xcframework "${xcargs[@]}" -output "$OUT/Libmpv.xcframework"
(cd "$OUT" && rm -f Libmpv.xcframework.zip && ditto -c -k --keepParent Libmpv.xcframework Libmpv.xcframework.zip)
echo "wrote $OUT/Libmpv.xcframework and .zip"
