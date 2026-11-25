---
name: edgecam-build-test
description: "Trigger: build, compile, run tests, simulator, monkeyc, monkeydo, check EdgeCam still works. Build the field and app for every Edge model and run the unit tests."
license: MIT
metadata:
  author: "mralexsaavedra"
  version: "1.0"
---

## Activation Contract

Load before compiling EdgeCam or claiming tests pass.

## Hard Rules

- SDK bin: `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-*/bin`; key: `~/.garmin/developer_key.der`.
- Delete old `*-test*.prg` before a test run; a failed test build leaves the previous binary and a false `PASSED`.
- Never compile with `-o /dev/null`: resources fail to cache; use a path in `bin/`.
- A missing result line means the simulator was still starting: restart it and rerun, do not report success.
- Report what is simulator-only; Bluetooth to the camera never runs in the simulator.

## Decision Gates

| Change touches | Build |
|---|---|
| `source/` | field (6 models) and app |
| `source-field/`, `resources-field*` | field (6 models) |
| `source-app/`, `source-rsdk/` | app (`edge540`) |

## Execution Steps

1. `rm -f bin/*-test*.prg`.
2. Field: `monkeyc -d <model> -f monkey.jungle -o bin/edgecam-field-<model>.prg -y <key>` and the same with
   `--unit-test` to `bin/edgecam-field-test-<model>.prg`, for edge540 edge840 edge550 edge850 edge1040 edge1050.
3. App: `monkeyc -d edge540 -f app.jungle -o bin/edgecam-app.prg -y <key>` (+ `--unit-test` build).
4. Restart the simulator: `pkill -f ConnectIQ.app; connectiq &`, wait for port 1234 (`nc -z 127.0.0.1 1234`).
5. `monkeydo bin/<test prg> <model> -t` per build; read the `PASSED (passed=N…)` line.
6. Copy `bin/edgecam-field-edge540.prg` to `bin/edgecam-field.prg` for installing on the owner's Edge.

## Output Contract

Return a table: model, build result, test result (passed/total). List any build errors verbatim.

## References

- `../../../docs/DEVELOPMENT.md` — layout, build and test commands.
