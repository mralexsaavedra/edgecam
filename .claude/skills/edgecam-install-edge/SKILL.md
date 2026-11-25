---
name: edgecam-install-edge
description: "Trigger: install on the Edge, copy to the Garmin, Edge connected, read Edge logs, FIT file. Copy EdgeCam builds to the Edge over USB (MTP) and read its logs."
license: MIT
metadata:
  author: "mralexsaavedra"
  version: "1.0"
---

## Activation Contract

Load when the owner says the Edge is connected, or a build must reach the Edge, or logs/FIT files must be read.

## Hard Rules

- Detect the Edge with `ioreg -p IOUSB -l -w0 | grep '"USB Product Name" = "Edge 540"'`; wait up to 40 s, then ask the
  owner to switch it on, plug it straight into the Mac and allow file transfer.
- `mtp-sendfile` cannot resolve Garmin paths: use `tools/mtpsend.c` (build it with libmtp) with the folder id.
- The Edge refuses a second file with the same name in `Garmin/Apps` (`PTP Access Denied`): delete the old copy in
  `Apps` first with `mtp-delfile -n <id>`. Copies in `Apps/Media` are installed apps: leave them.
- Folder ids change between connections: read them each time with `mtp-folders`.
- Verify by comparing the size on the Edge (`mtp-files`) with the local file.

## Decision Gates

| Goal | Target name in `Garmin/Apps` |
|---|---|
| Data field | `EDGECAMF.PRG` (from `bin/edgecam-field.prg` or `dist/EdgeCam-edge540.prg`) |
| Debug app | `EDGECAM.PRG` (from `bin/edgecam-app.prg`) |
| Field log | read `Garmin/Apps/LOGS/EDGECAMF.TXT` (`mtp-getfile <id> <out>`) |
| Activity | `Garmin/Activity/<date>-<time>.fit`, then parse developer fields |

## Execution Steps

1. `mtp-folders` → ids of `Apps` and `LOGS`; `mtp-files` → ids/sizes of existing `EDGECAM*` files.
2. Delete an `EDGECAMF.PRG` / `EDGECAM.PRG` whose parent is `Apps`.
3. `mtpsend <local> <NAME> <apps id>`; check the size on the Edge.
4. Tell the owner to unplug (the Edge installs on disconnect) and what to test; remind them to discard test
   activities or they sync to Garmin Connect, Strava and TrainingPeaks.

## Output Contract

Return what was copied (name, size on Edge = local size) and the owner's next steps.

## References

- `../../../docs/DEVELOPMENT.md` — install and log sections.
- `../../../tools/mtpsend.c` — the copy helper.
