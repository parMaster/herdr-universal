# GitHub Actions builder for universal Herdr

**Goal:** GitHub Actions builds and publishes universal Herdr.app releases, and an Intel Mac installs the latest one with a single `curl | bash`.

**Kind of change:** feature

## Intent

Today a universal build means running `build-universal.sh` by hand on an Apple Silicon Mac. Then the
archive gets copied to the Intel Mac. The script is proven: it built on an M3 with no fixes, and the app
runs and renders on a 2015 Intel MacBook Pro with Sonoma 14.6. This change moves the build to GitHub
Actions, the same way agterm-universal works. Each new herdr-app tag gets built on its own, and
`install.sh` downloads releases from this repo.

```
daily check-upstream ── new v* tag, no <tag>-universal release ──► dispatch build-universal
                                                                       │
build-universal (macos-15): build-universal.sh <tag> → verify → release <tag>-universal
                                                                       │ fail + report_failure
                                                                       └──► issue "Universal build failed for upstream <tag>"

Intel Mac: curl …/install.sh | bash [tag] ──► download Herdr-<tag>-universal.tar.gz ──► ~/Applications/Herdr.app
```

## Decisions

- **The repo becomes public.** macOS minutes are free on public repos. On private repos they count 10x against the 2,000 min/month quota. A public repo also allows anonymous release downloads for `curl | bash`. herdr-app is Apache-2.0, and the bundle already ships `LICENSE` and `THIRD-PARTY-NOTICES`.
- **The workflow runs `build-universal.sh` unchanged in logic.** No upstream patch, unlike agterm-universal. A local build and a CI build stay the same code path.
- **Use upstream tags, not upstream releases.** herdr-app publishes no GitHub releases; it ships through releases.herdr.dev. check-upstream takes the highest `v<digits>.<digits>.<digits>` tag from `git ls-remote`.
- **Name the asset by tag:** `Herdr-<tag>-universal.tar.gz` (for example `Herdr-v0.1.15-universal.tar.gz`), in release `<tag>-universal`. install.sh builds the URL from the tag alone. The build fails if the tag isn't `v` + the Cargo.toml version, so the name can't lie.
- **Keep a tarball, not a zip.** It is already the script's output, and install.sh already unpacks it.
- **One rule picks the "latest" tag:** the highest strict `v<d>.<d>.<d>` tag, by semver. Both workflows resolve the tag with this rule, and `build-universal.sh` uses it as its own default. The build workflow always passes an explicit tag to the script, because it needs the tag to name the release. No pin is needed, because there's no patch.
- **The archs and minos checks live in `build-universal.sh`, and they fail hard.** A missing slice, or a minos above `MACOSX_DEPLOYMENT_TARGET`, exits non-zero, so local builds get the same guard. In CI the error also prints as `::error::`.
- **Only the highest tag's release is marked "latest".** The workflow publishes with `--latest=false` when it rebuilds an older tag. Then `curl | bash` never downgrades.
- **install.sh takes three forms:** no argument means the latest release, a tag means that release, and an existing `.tar.gz` path means a local archive (today's behavior, kept for M3 test builds).
- **No cargo cache in CI for now.** A build runs once per upstream tag, so a cache would rarely hit. Add one only if build time hurts.

## Constraints / out of scope

- `build-universal.sh` keeps working locally on an Apple Silicon Mac, with the same flags and output.
- No signing or notarization. Builds stay ad hoc, and install.sh keeps removing the quarantine flag.
- No herdr-core repackaging. It ships Intel builds itself.
- `HERDR_APP_RELEASE` stays unset, so self-update and telemetry stay off.

## Traps

- herdr-app has no GitHub releases, so `gh release view --repo herdrdev/herdr-app` fails. agterm-universal's check-upstream uses that call, so don't copy it as is.
- Today `build-universal.sh` names its output `Herdr-<Cargo version>-universal.tar.gz` (`--- bundle ---` section). The release asset uses the tag name, so either the script or the workflow has to rename it.
- `build-universal.sh` reads the Rust version from upstream's `.github/workflows/ci.yml` (`RUST_TOOLCHAIN:`). If upstream moves that key, the build dies with "cannot read RUST_TOOLCHAIN". The failure issue covers this case.
- `install.sh` writes the installing shell's `$PATH` into `LSEnvironment`. Under `curl | bash`, that is the PATH of a non-login bash. The plist already adds `~/.local/bin`, `/usr/local/bin` and `/opt/homebrew/bin`, which covers `hc`. Keep those.
- `install.sh` today needs a file argument (`${1:?…}`). A bare `curl | bash` must not trip that check.
- `build-universal.sh` today defaults to `git tag --list 'v*' --sort=-v:refname | head -1`. That includes pre-release tags, and version sort can rank `v1.0.0-rc1` above `v1.0.0` (`--- source ---` section).
- `install.sh` in agterm-universal finds "latest" by following the `/releases/latest` redirect. GitHub marks the newest-created release as latest, not the highest version. A delete-and-recreate rebuild of an old tag would take over "latest" unless it's published with `--latest=false`.
- A `GITHUB_TOKEN` can trigger `workflow_dispatch`, but not other events. check-upstream must dispatch the build by workflow file name, as agterm-universal does.
- GitHub disables scheduled workflows after 60 days with no repo activity. The README should say so, as agterm-universal's does.

## Definition of Done

- [ ] The repo is public — proof: `gh api repos/parMaster/herdr-universal --jq .visibility` prints `public`
- [ ] A manual build of `v0.1.15` publishes release `v0.1.15-universal` with `Herdr-v0.1.15-universal.tar.gz` — proof: `gh release view v0.1.15-universal` lists the asset
- [ ] `build-universal.sh` exits non-zero if the binary isn't arm64 + x86_64, or if a slice's minos is above `MACOSX_DEPLOYMENT_TARGET` — proof: on the M3, run the check against a one-slice binary (`lipo -thin arm64`) and see it fail; read the minos comparison; the v0.1.15 run log shows both checks passing
- [ ] With no tag given, the script and both workflows pick the same tag, and they skip pre-release tags — proof: the resolve step logs `v0.1.15`, the same tag the script picks on its own
- [ ] Rebuilding an older tag leaves the "latest" release unchanged — proof: the workflow sets `--latest=false` unless the tag is the highest; reading the step is enough
- [ ] A tag that doesn't match the Cargo.toml version fails the build before the release step — proof: the check is visible in the workflow, and `v0.1.15` passes it
- [ ] check-upstream does nothing when the latest tag already has a release — proof: a manual run after the v0.1.15 release logs "already released"
- [ ] check-upstream dispatches a build when the latest tag has no release — proof: a manual run before the first release (or after deleting it) starts a build-universal run with `report_failure=true`
- [ ] A failed build with `report_failure` opens one issue per tag, and no duplicates. check-upstream skips the dispatch while that issue is open, so a broken tag doesn't rebuild every day — proof: both steps mirror agterm-universal's title search
- [ ] `curl -fsSL https://raw.githubusercontent.com/parMaster/herdr-universal/main/install.sh | bash` installs the latest release on the Intel Mac — proof: the run on the 2015 MBP, then Herdr opens
- [ ] `install.sh v0.1.15` and `install.sh <local .tar.gz>` both still work — proof: run each once
- [ ] The README documents the Actions build, the one-line install, and the 60-day schedule caveat — proof: read it

## Work order

1. Make the repo public. Then the first Actions run uses free minutes.
2. Add the build workflow, then run it for `v0.1.15`.
3. Change install.sh, then test it against that release.
4. Add check-upstream, then run it manually.

## Wrap-up

- [ ] `bash -n` passes for both scripts; `shellcheck` and `actionlint` pass where available
- [ ] README.md updated
- [ ] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv docs/plans/2026-11-13-actions-builder.md docs/plans/completed/`)
- [ ] commits: one per work-order step, because a workflow must be on `main` before it can be dispatched; the last commit moves the plan

## Post-Completion

- Watch the first scheduled check-upstream run after herdr-app's next tag.
