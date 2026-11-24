#!/usr/bin/env bash
# hbak fork: build AeroSpace.app + the aerospace CLI from this checkout and install them over the
# Homebrew copy (/Applications/AeroSpace.app, /opt/homebrew/bin/aerospace). Skips docs and shell
# completions (upstream's build-release.sh), which need Ruby and Rust and aren't needed to run.
#
#   ./hbak-build.sh            build into .hbak-release/
#   ./hbak-build.sh --install  build, install, restart AeroSpace
#
# Signs with the self-signed "aerospace-codesign-certificate" in the login keychain (by hash: it is
# deliberately not trusted system-wide). macOS keys AeroSpace's Accessibility permission to that
# certificate, so rebuilds keep it. Builds with Xcode's Swift; upstream pins a newer toolchain in
# .swift-version (swiftly), which is used instead when installed.
set -euo pipefail
cd "$(dirname "$0")"

install=0
[[ "${1:-}" == --install ]] && install=1

identity=$(security find-identity -p codesigning | awk '/"aerospace-codesign-certificate"/ { print $2; exit }')
[[ -n "$identity" ]] || { echo "no aerospace-codesign-certificate in the keychain" >&2; exit 1; }

upstream_version=$(git describe --tags --abbrev=0 --match 'v*' | sed 's/^v//')
version="$upstream_version+hbak.$(git rev-parse --short HEAD)"
out="$PWD/.hbak-release"
[[ -e "$out" ]] && trash "$out"
mkdir -p "$out"
build_info="$out/build-info.txt"
printf '%s\n%s\n%s\n' "$version" "$(git rev-parse HEAD)" "$(git rev-parse --short HEAD)" > "$build_info"

# This release reads its version from generated sources (newer upstream uses the __aero_build
# section above); stamp them for the build and restore them after.
version_files=(Sources/Common/versionGenerated.swift Sources/Common/gitHashGenerated.swift)
trap 'git checkout -q -- "${version_files[@]}"' EXIT
sed -i '' "s|^public let aeroSpaceAppVersion = .*|public let aeroSpaceAppVersion = \"$version\"|" Sources/Common/versionGenerated.swift
sed -i '' "s|^public let gitHash = .*|public let gitHash = \"$(git rev-parse HEAD)\"|" Sources/Common/gitHashGenerated.swift

echo "building AeroSpace $version"
(
  cd xcode
  /usr/bin/xcrun xcodebuild build -quiet \
    -scheme AeroSpace -destination "generic/platform=macOS" -configuration Release \
    -derivedDataPath .xcode-build \
    MARKETING_VERSION="$version" \
    AEROSPACE_CODE_SIGN_IDENTITY="-" \
    AEROSPACE_BUILD_INFO_LDFLAGS="-sectcreate __TEXT __aero_build $build_info"
)
cp -R xcode/.xcode-build/Build/Products/Release/AeroSpace.app "$out/"
codesign -f --deep -s "$identity" --entitlements resources/AeroSpace.entitlements "$out/AeroSpace.app"

swift=(swift)
if command -v swiftly > /dev/null && swiftly list 2> /dev/null | grep -qF "$(cat .swift-version)"; then
  swift=(swiftly run swift "+$(cat .swift-version)")
fi
# Force a relink: SwiftPM reuses a cached binary when only linker flags change, which drops the
# version info section and makes the CLI report 0.0.0-SNAPSHOT.
cli_bin_dir=$("${swift[@]}" build -c release --product aerospace --show-bin-path)
[[ -e "$cli_bin_dir/aerospace" ]] && trash "$cli_bin_dir/aerospace"
"${swift[@]}" build -c release --product aerospace \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __aero_build -Xlinker "$build_info"
cp "$cli_bin_dir/aerospace" "$out/aerospace"
codesign -f -s "$identity" "$out/aerospace"
echo "built: $out/AeroSpace.app $out/aerospace"

(( install )) || exit 0
osascript -e 'quit app "AeroSpace"' 2> /dev/null || true
sleep 1
[[ -e /Applications/AeroSpace.app ]] && trash /Applications/AeroSpace.app
cp -R "$out/AeroSpace.app" /Applications/
# The brew cask's CLI is a symlink into the cask's app; replace it with this build's binary.
[[ -e /opt/homebrew/bin/aerospace || -L /opt/homebrew/bin/aerospace ]] && trash /opt/homebrew/bin/aerospace
cp "$out/aerospace" /opt/homebrew/bin/aerospace
open -a /Applications/AeroSpace.app
echo "installed $version"
