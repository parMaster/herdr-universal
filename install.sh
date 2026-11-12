#!/bin/bash
# Install (or update to) a universal Herdr.app, on any Mac.
#
#   install.sh                       -> latest release of this repo
#   install.sh v0.1.15               -> that release (v0.1.15 or v0.1.15-universal)
#   install.sh path/to/archive.tar.gz -> a local build from build-universal.sh
#
# Works piped: curl -fsSL https://raw.githubusercontent.com/parMaster/herdr-universal/main/install.sh | bash
# Installs the same way upstream's scripts/install-macos does after its build step.
set -euo pipefail

repo=parMaster/herdr-universal
die() { echo "install: $*" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

arg=${1:-}
if [[ -n $arg && -f $arg ]]; then
  archive=$arg
else
  tag=$arg
  if [[ -z $tag ]]; then
    # The redirect target carries the tag; the REST API would rate-limit anonymous callers.
    latest_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest") \
      || die "could not look up the latest release of $repo"
    tag=${latest_url##*/}
    [[ $tag == *-universal ]] || die "could not read a release tag from $latest_url"
  fi
  tag=${tag%-universal}
  url="https://github.com/$repo/releases/download/$tag-universal/Herdr-$tag-universal.tar.gz"
  echo "downloading $url"
  archive=$work/Herdr.tar.gz
  curl -fsSL -o "$archive" "$url" || die "no release $tag-universal in $repo (tried $url)"
fi

tar -xzf "$archive" -C "$work"
[[ -d $work/Herdr.app ]] || die "$archive has no Herdr.app in it"
# Ad hoc signed, not notarized: Gatekeeper blocks it while a quarantine flag is set.
xattr -cr "$work/Herdr.app"
# Checked before anything installed is touched, so a bad download leaves the working app alone.
lipo "$work/Herdr.app/Contents/MacOS/Herdr" -verify_arch "$(uname -m)" \
  || die "this build has no $(uname -m) slice"

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
echo "Installed $app ($(defaults read "$app/Contents/Info" CFBundleShortVersionString), $(lipo -archs "$app/Contents/MacOS/Herdr"))."
echo "A running Herdr keeps the old version until you quit and reopen it."

if ! command -v hc >/dev/null && [[ ! -x $HOME/.local/bin/hc ]]; then
  echo
  echo "herdr-core (hc) is not installed. It ships Intel builds:"
  echo "  curl -fsSL https://releases.herdr.dev/core/install.sh | sh"
fi
