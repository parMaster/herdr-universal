# herdr-universal

Unofficial universal (arm64 + x86_64) builds of [herdrdev/herdr-app](https://github.com/herdrdev/herdr-app),
so it runs on Intel Macs too. Upstream ships Apple Silicon builds only.

## Build (on an Apple Silicon Mac)

Needs git, the Xcode Command Line Tools and [rustup](https://rustup.rs). Full Xcode is not needed.

```bash
./build-universal.sh            # latest v* tag
./build-universal.sh v0.1.15    # a specific tag, branch or commit
```

The script clones herdr-app into `work/` and installs the Rust version upstream CI pins, with both
macOS targets. It fetches Zig 0.16 into `.tools/` when the `zig` on PATH is another version. It
builds both arches with `MACOSX_DEPLOYMENT_TARGET=14.0` and joins them with `lipo`. The result is
`dist/Herdr-<version>-universal.tar.gz`, signed ad hoc.

The build leaves `HERDR_APP_RELEASE` unset, so self-update and telemetry stay off. Upstream's
update manifest has no Intel entry, so updates come from re-running the build.

## Install (on any Mac)

```bash
./install.sh Herdr-0.1.15-universal.tar.gz
```

It installs `~/Applications/Herdr.app` the same way upstream's `scripts/install-macos` does. The app
also needs [herdr-core](https://github.com/herdrdev/herdr-core) (`hc`), which ships Intel builds:

```bash
curl -fsSL https://releases.herdr.dev/core/install.sh | sh
```
