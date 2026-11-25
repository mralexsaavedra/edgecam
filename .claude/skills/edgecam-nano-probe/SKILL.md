---
name: edgecam-nano-probe
description: "Trigger: new camera command, battery, storage, GPS, marker, DUML, capture, PacketLogger, nanoprobe, what does the Nano send. Discover or check Osmo Nano DUML commands."
license: MIT
metadata:
  author: "mralexsaavedra"
  version: "1.0"
---

## Activation Contract

Load before adding a feature that needs a camera command or data not yet in `docs/PROTOCOL.md`.

## Hard Rules

- Check `docs/PROTOCOL.md` first: many commands are already known or known to be unsupported (`e0`).
- Read-only queries are fine; ask the owner before sending any command that changes the camera.
- Data must fit the Edge: payload bytes 0-8 of a frame only (20-byte notifications, 11-byte header).
- Never commit captures: they hold the camera's Wi-Fi password and device addresses; delete them after use.
- Command names: dji-firmware-tools `comm_dissector/wireshark/dji-dumlv1-*.lua`; treat them as hints, confirm on
  the camera.

## Decision Gates

| Situation | Path |
|---|---|
| An app already does it over Bluetooth | Capture it (PacketLogger, iOS Bluetooth logging profile) |
| Candidate command known | Send it from the Mac with `tools/nanoprobe.py` |
| Only DJI Mimo does it | It is over Wi-Fi: not reachable from Connect IQ |

## Execution Steps

1. Mac bench: venv with `bleak`; the owner runs `python tools/nanoprobe.py` from a terminal with Bluetooth
   permission (macOS kills it otherwise); the camera must be free (no phone app, no Edge session).
2. Capture: owner installs Apple's iOS Bluetooth logging profile and PacketLogger (Apple ID needed), records,
   saves a `.pklg`; parse ACL → ATT (handle of the Nano), decode DUML, verify CRC8/CRC16 on every frame.
3. Correlate commands with what the owner did (timestamps), confirm with a second run.
4. Add the finding to `docs/PROTOCOL.md` and a test with the captured bytes.

## Output Contract

Return the command (set/id, direction, payload layout), evidence (capture or probe reply), whether it fits the
Edge's 9 payload bytes, and the doc/test changes.

## References

- `../../../docs/PROTOCOL.md` — known commands, frame format, Connect IQ limits.
- `../../../tools/nanoprobe.py` — Mac test bench.
