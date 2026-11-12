#!/bin/bash
# Install a Herdr.app built by build-universal.sh, on any Mac.
#
#   ./install.sh dist/Herdr-0.1.15-universal.tar.gz
#
# Does what upstream's scripts/install-macos does after its build step.
set -euo pipefail

archive=${1:?usage: install.sh Herdr-<version>-universal.tar.gz}
[[ -f $archive ]] || { echo "install: $archive not found" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xzf "$archive" -C "$work"
xattr -dr com.apple.quarantine "$work/Herdr.app" 2>/dev/null || true
lipo "$work/Herdr.app/Contents/MacOS/Herdr" -verify_arch "$(uname -m)" \
  || { echo "install: this build has no $(uname -m) slice" >&2; exit 1; }

app="$HOME/Applications/Herdr.app"
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
rm -rf "$app.new"
cp -R "$work/Herdr.app" "$app.new"
# Finder does not inherit a login shell's PATH; hc must still be discoverable.
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:PATH string $HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH" \
  "$app.new/Contents/Info.plist"
codesign --force --sign - "$app.new"
rm -rf "$app"
mv "$app.new" "$app"
ln -sfn "$app/Contents/MacOS/Herdr" "$HOME/.local/bin/herdr-app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
echo "Installed $app ($(defaults read "$app/Contents/Info" CFBundleShortVersionString))."

if ! command -v hc >/dev/null && [[ ! -x $HOME/.local/bin/hc ]]; then
  echo
  echo "herdr-core (hc) is not installed. It ships Intel builds:"
  echo "  curl -fsSL https://releases.herdr.dev/core/install.sh | sh"
fi
