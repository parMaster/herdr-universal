#!/bin/bash
# Build a universal (arm64 + x86_64) Herdr.app on an Apple Silicon Mac.
#
#   ./build-universal.sh            -> latest v* tag of herdr-app
#   ./build-universal.sh v0.1.15    -> that tag (or any branch/commit)
#
# Needs: git, Xcode Command Line Tools, rustup. Zig 0.16 is fetched into
# .tools/ when the zig on PATH is another version (set ZIG to override).
# Output: dist/Herdr-<version>-universal.tar.gz, ad hoc signed.
#
# The build leaves HERDR_APP_RELEASE unset: upstream's update manifest has no
# macos-x86_64 entry, and the flag would also turn on telemetry.
set -euo pipefail
cd "$(dirname "$0")"
root=$PWD

ref=${1:-}
repo=https://github.com/herdrdev/herdr-app.git
src=$root/work/herdr-app
zig_version=0.16.0
# Oldest macOS the binary loads on; the build SDK is newer than an Intel Mac's OS.
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-14.0}

log() { printf '\n==> %s\n' "$*"; }
die() { echo "build-universal: $*" >&2; exit 1; }

[[ $(uname -s) == Darwin ]] || die "run this on macOS"
command -v rustup >/dev/null || die "rustup missing: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
xcrun --show-sdk-path >/dev/null || die "Command Line Tools missing: xcode-select --install"

# --- source ---------------------------------------------------------------
if [[ ! -d $src/.git ]]; then
  log "cloning herdr-app"
  mkdir -p "$root/work"
  git clone "$repo" "$src"
fi
git -C "$src" fetch --tags --force origin
if [[ -z $ref ]]; then
  ref=$(git -C "$src" tag --list 'v*' --sort=-v:refname | head -1)
  [[ -n $ref ]] || die "no v* tags found"
fi
log "checking out $ref"
git -C "$src" checkout --force --detach "$ref"
git -C "$src" submodule update --init --recursive --force

version=$(sed -n 's/^version = "\(.*\)"/\1/p' "$src/Cargo.toml" | head -1)
rust=$(sed -n 's/^ *RUST_TOOLCHAIN: *//p' "$src/.github/workflows/ci.yml" | head -1)
[[ -n $rust ]] || die "cannot read RUST_TOOLCHAIN from ci.yml"

# --- toolchains -----------------------------------------------------------
log "rust $rust with both macOS targets"
rustup toolchain install "$rust" --profile minimal \
  --target aarch64-apple-darwin --target x86_64-apple-darwin
export RUSTUP_TOOLCHAIN=$rust

if [[ -z ${ZIG:-} ]]; then
  if [[ $(zig version 2>/dev/null || true) == "$zig_version" ]]; then
    ZIG=zig
  else
    zdir=$root/.tools/zig-$zig_version
    if [[ ! -x $zdir/zig ]]; then
      log "fetching zig $zig_version"
      mkdir -p "$zdir"
      host="$(uname -m | sed 's/arm64/aarch64/')-macos"
      index=$(curl -fsSL https://ziglang.org/download/index.json)
      read -r url sum < <(python3 -I -c '
import json, sys
e = json.loads(sys.stdin.read())[sys.argv[1]][sys.argv[2]]
print(e["tarball"], e["shasum"])' "$zig_version" "$host" <<<"$index")
      curl -fsSL "$url" -o "$zdir.tar.xz"
      [[ $(shasum -a 256 "$zdir.tar.xz" | cut -d' ' -f1) == "$sum" ]] || die "zig checksum mismatch"
      tar -xJf "$zdir.tar.xz" -C "$zdir" --strip-components=1
      rm "$zdir.tar.xz"
    fi
    ZIG=$zdir/zig
  fi
fi
export ZIG
log "zig: $("$ZIG" version) ($ZIG)"

# --- build ----------------------------------------------------------------
unset HERDR_APP_RELEASE
for triple in aarch64-apple-darwin x86_64-apple-darwin; do
  log "cargo build $triple (macOS >= $MACOSX_DEPLOYMENT_TARGET)"
  (cd "$src" && cargo build --release --locked --target "$triple")
done

# --- bundle ---------------------------------------------------------------
log "lipo + bundle"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
app=$work/Herdr.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create \
  "$src/target/aarch64-apple-darwin/release/herdr-app" \
  "$src/target/x86_64-apple-darwin/release/herdr-app" \
  -output "$app/Contents/MacOS/Herdr"
cp "$src/assets/icons/Herdr.icns" "$app/Contents/Resources/Herdr.icns"
cp "$src/LICENSE" "$src/THIRD-PARTY-NOTICES" "$app/Contents/Resources/"
# Same Info.plist as upstream's scripts/package, plus the minimum macOS version.
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>Herdr</string>
    <key>CFBundleIdentifier</key><string>dev.herdr.app</string>
    <key>CFBundleName</key><string>Herdr</string>
    <key>CFBundleDisplayName</key><string>Herdr</string>
    <key>CFBundleIconFile</key><string>Herdr</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>$MACOSX_DEPLOYMENT_TARGET</string>
    <key>NSMicrophoneUsageDescription</key><string>Terminal programs running in Herdr can use the microphone, for example for voice input.</string>
    <key>NSCameraUsageDescription</key><string>Terminal programs running in Herdr can use the camera.</string>
    <key>NSAppleEventsUsageDescription</key><string>Terminal programs running in Herdr can use AppleScript to control other apps.</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSEnvironment</key><dict/></dict></plist>
PLIST
codesign --force --sign - "$app"
codesign --verify --strict "$app"

mkdir -p "$root/dist"
out=$root/dist/Herdr-$version-universal.tar.gz
tar -czf "$out" -C "$work" Herdr.app

# --- report ---------------------------------------------------------------
log "result"
echo "archs:   $(lipo -archs "$app/Contents/MacOS/Herdr")"
for arch in arm64 x86_64; do
  minos=$(vtool -arch "$arch" -show-build "$app/Contents/MacOS/Herdr" 2>/dev/null | awk '/minos/ {print $2; exit}')
  echo "minos:   $arch $minos"
done
echo "archive: $out"
echo "sha256:  $(shasum -a 256 "$out" | cut -d' ' -f1)"
