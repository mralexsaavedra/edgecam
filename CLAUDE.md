# EdgeCam

Connect IQ data field for Garmin Edge that controls a DJI Osmo Nano over Bluetooth LE: Lap starts/stops recording,
the field shows state, estimated battery and free storage, raises alerts and writes clip data to the FIT file.

Read first: [README.md](README.md) (what it does), [docs/PROTOCOL.md](docs/PROTOCOL.md) (DUML and the Nano),
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) (layout, build, tests, install).

## Skills

| Skill | Use it to |
|---|---|
| [edgecam-build-test](.claude/skills/edgecam-build-test/SKILL.md) | Build the field/app for every model and run the simulator tests |
| [edgecam-install-edge](.claude/skills/edgecam-install-edge/SKILL.md) | Copy a build onto the owner's Edge over USB and read its logs |
| [edgecam-release](.claude/skills/edgecam-release/SKILL.md) | Bump the version and build the release files |
| [edgecam-nano-probe](.claude/skills/edgecam-nano-probe/SKILL.md) | Discover or check Nano commands from a Mac or a Bluetooth capture |

## Hard facts (do not relearn them)

- The Nano ignores DJI's documented R SDK; it speaks **DUML** (`0x55` frames) on `FFF0`/`FFF5`/`FFF4`.
- Connect IQ writes **at most 20 bytes** per write and delivers **only the first 20 bytes** of each notification
  (11-byte header + 9 payload bytes). Anything beyond payload byte 8 is out of reach on the Edge.
- Data fields cannot use timers or read buttons: `compute()` (1/s) is the clock, `onTimerLap` is the control, and
  neither reaches the field while the activity is paused.
- The Nano does not support GPS or highlight markers (`e0` to every variant tried).
- The SDK Manager downloads every device when opened; afterwards keep only the six supported Edge models
  (`edge540`, `edge840`, `edge550`, `edge850`, `edge1040`, `edge1050`) and their fonts.

## Rules

- Code, comments, docs, commits: English. Talk to the owner in Spanish (Spain). User-facing strings exist in English
  (`resources-field/`) and Spanish (`resources-field-spa/`): change both.
- Conventional commits, no AI attribution. Publishing (push, GitHub repo, releases, Connect IQ Store) only when the
  owner asks.
- Test-first for behaviour changes; a test build must be rebuilt fresh before trusting `PASSED` (stale `.prg` files
  report old results).
- Anything that touches the camera can only be proven on the real Edge + Nano; say what was simulator-only.
- Never write an unknown DUML command to the camera without asking: read-only queries (`Get`) are fine.
- Never commit Bluetooth captures (`.pklg`), keys (`*.der`, `*.pem`) or camera identifiers; captures can hold the
  camera's Wi-Fi password.
- Keep the developer key (`~/.garmin/developer_key.der`): the Edge only updates an app signed with the same key.
- Test activities saved on the Edge sync to Garmin Connect, Strava and TrainingPeaks: ask the owner to discard them,
  or remove them afterwards.
