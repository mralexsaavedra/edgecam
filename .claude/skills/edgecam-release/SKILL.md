---
name: edgecam-release
description: "Trigger: release, new version, bump version, changelog, dist, Connect IQ Store package, .iq. Prepare an EdgeCam release locally."
license: MIT
metadata:
  author: "mralexsaavedra"
  version: "1.0"
---

## Activation Contract

Load when preparing a new EdgeCam version or its release files.

## Hard Rules

- Prepare locally only. Pushing, creating the GitHub release or uploading to the Connect IQ Store needs the owner's
  explicit go-ahead.
- Run `edgecam-build-test` first; all six models must pass.
- Release builds use `-r` (no debug info); sign with the same developer key as before.
- `dist/` is git-ignored; never commit build outputs.

## Execution Steps

1. Bump `version` in `manifest.xml` (semver; beta stays `0.x`).
2. Add a `CHANGELOG.md` entry: English list, then a one-paragraph Spanish summary; say which models were tested on
   hardware and which only in the simulator.
3. `rm -rf dist && mkdir dist`; for each model `monkeyc -r -d <model> -f monkey.jungle -o dist/EdgeCam-<model>.prg -y <key>`.
4. `monkeyc -e -r -f monkey.jungle -o dist/EdgeCam.iq -y <key>`.
5. Remove `dist/` side outputs (`gen`, `*-mir`, `*.debug.xml`, `*-fit_contributions.json`, `*-settings.json`).
6. `cd dist && shasum -a 256 *.prg *.iq > SHA256SUMS`.
7. Smoke-run one small and one large model in the simulator (`monkeydo dist/EdgeCam-<model>.prg <model>`), no errors.
8. Commit version, changelog and doc changes.

## Output Contract

Return the version, the files in `dist/` with sizes, the smoke-run result and the commit hash.

## References

- `../../../docs/DEVELOPMENT.md` — release build commands.
- `../../../CHANGELOG.md` — previous entries.
