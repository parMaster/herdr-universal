# herdr-universal

Unofficial universal (arm64 + x86_64) builds of [herdrdev/herdr-app](https://github.com/herdrdev/herdr-app),
so it runs on Intel Macs too. Upstream ships Apple Silicon builds only.

This repo carries no copy of herdr-app's source and no patch. `build-universal.sh` clones upstream
at a tag, builds it for both arches, and joins the two binaries with `lipo`. Builds are ad hoc signed,
not notarized. Self-update and telemetry are off (`HERDR_APP_RELEASE` stays unset), so updates come
from this repo.

## Installing (or updating)

One command, the same on Apple Silicon and Intel Macs:

```bash
curl -fsSL https://raw.githubusercontent.com/parMaster/herdr-universal/main/install.sh | bash
```

That installs the latest release to `~/Applications/Herdr.app`. To install a specific one, pass its
tag, with or without the `-universal` suffix:

```bash
curl -fsSL https://raw.githubusercontent.com/parMaster/herdr-universal/main/install.sh | bash -s -- v0.1.15
```

From a clone, `./install.sh [tag]` does the same, and `./install.sh dist/Herdr-v0.1.15-universal.tar.gz`
installs a local build. A running Herdr keeps the old version until you quit and reopen it.

The app also needs [herdr-core](https://github.com/herdrdev/herdr-core) (`hc`), which ships Intel builds:

```bash
curl -fsSL https://releases.herdr.dev/core/install.sh | sh
```

## Getting a build

Go to Actions → "Build universal Herdr" → "Run workflow". Leave `herdr_ref` empty to build upstream's
highest `vX.Y.Z` tag, or name a tag. The build attaches `Herdr-<tag>-universal.tar.gz` to a release
tagged `<tag>-universal`. Rebuilding an older tag doesn't make it "latest", so the installer never
downgrades.

### Automatic builds of new upstream tags

`.github/workflows/check-upstream.yml` runs daily (and on demand from the Actions tab). It finds
upstream's highest `vX.Y.Z` tag, and does nothing if `<tag>-universal` already exists here. Otherwise it
dispatches "Build universal Herdr". If that build fails, it opens an issue titled
`Universal build failed for upstream <tag>`. While that issue is open, the daily check won't retry;
close it to let it try again.

GitHub disables scheduled workflows after 60 days with no repo activity. If upstream goes quiet that
long, re-enable the workflow from the Actions tab.

## Building locally (on an Apple Silicon Mac)

Needs git, the Xcode Command Line Tools and [rustup](https://rustup.rs). Full Xcode is not needed.

```bash
./build-universal.sh            # highest vX.Y.Z tag
./build-universal.sh v0.1.15    # a specific tag, branch or commit
```

The script clones herdr-app into `work/` and installs the Rust version upstream CI pins, with both
macOS targets. It fetches Zig 0.16 into `.tools/` when the `zig` on PATH is another version. It builds
both arches with `MACOSX_DEPLOYMENT_TARGET=14.0`. It fails if the result lacks a slice, or if a slice
needs a newer macOS than that. `./build-universal.sh --verify <binary>` runs only that check. The
result is `dist/Herdr-v<version>-universal.tar.gz`.
