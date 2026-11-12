#!/bin/bash
# Build a universal (arm64 + x86_64) Herdr.app on an Apple Silicon Mac.
#
#   ./build-universal.sh                  -> highest vX.Y.Z tag of herdr-app
#   ./build-universal.sh v0.1.15          -> that tag (or any branch/commit)
#   ./build-universal.sh --verify <bin>   -> only run the universal/minos checks
#
# Needs: git, Xcode Command Line Tools, rustup. Zig 0.16 is fetched into
# .tools/ when the zig on PATH is another version (set ZIG to override).
# Output: dist/Herdr-v<version>-universal.tar.gz, ad hoc signed.
#
# The build leaves HERDR_APP_RELEASE unset: upstream's update manifest has no
# macos-x86_64 entry, and the flag would also turn on telemetry.
set -euo pipefail
cd "$(dirname "$0")"
root=$PWD

repo=https://github.com/herdrdev/herdr-app.git
src=$root/work/herdr-app
zig_version=0.16.0
# Oldest macOS the binary loads on; the build SDK is newer than an Intel Mac's OS.
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-14.0}

log() { printf '\n==> %s\n' "$*"; }
die() {
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then echo "::error::$*"; fi
  echo "build-universal: $*" >&2
  exit 1
}

# Release tags only: a pre-release such as v1.0.0-rc1 is never "latest".
latest_tag() { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1; }

# Fails unless the binary has both slices and each loads on MACOSX_DEPLOYMENT_TARGET.
verify_binary() {
  local bin=$1 archs arch minos highest
  archs=$(lipo -archs "$bin")
  echo "archs:   $archs"
  for arch in arm64 x86_64; do
    [[ " $archs " == *" $arch "* ]] || die "$bin has no $arch slice (archs: $archs)"
    minos=$(vtool -arch "$arch" -show-build "$bin" | awk '/minos/ {print $2; exit}')
    [[ -n $minos ]] || die "$bin: cannot read minos of the $arch slice"
    echo "minos:   $arch $minos"
    highest=$(printf '%s\n%s\n' "$minos" "$MACOSX_DEPLOYMENT_TARGET" | sort -V | tail -1)
    [[ $highest == "$MACOSX_DEPLOYMENT_TARGET" ]] \
      || die "$bin: $arch slice needs macOS $minos, above $MACOSX_DEPLOYMENT_TARGET"
  done
}

if [[ ${1:-} == --verify ]]; then
  verify_binary "${2:?usage: build-universal.sh --verify <binary>}"
  exit 0
fi
ref=${1:-}

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
  ref=$(git -C "$src" tag --list 'v*' | latest_tag)
  [[ -n $ref ]] || die "no vX.Y.Z tags found"
fi
log "checking out $ref"
git -C "$src" checkout --force --detach "$ref"
git -C "$src" submodule update --init --recursive --force

version=$(sed -n 's/^version = "\(.*\)"/\1/p' "$src/Cargo.toml" | head -1)
# The archive is named after the version; a tag must agree with it.
if git -C "$src" show-ref --verify --quiet "refs/tags/$ref" && [[ $ref != "v$version" ]]; then
  die "tag $ref does not match Cargo.toml version $version"
fi
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
log "verify"
verify_binary "$app/Contents/MacOS/Herdr"
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
out=$root/dist/Herdr-v$version-universal.tar.gz
tar -czf "$out" -C "$work" Herdr.app

log "result"
echo "archive: $out"
echo "sha256:  $(shasum -a 256 "$out" | cut -d' ' -f1)"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then echo "archive=$out" >> "$GITHUB_OUTPUT"; fi
