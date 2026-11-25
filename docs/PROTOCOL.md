# How EdgeCam talks to the Osmo Nano

Notes for developers. Nothing here comes from DJI documentation for the Nano: it was worked out by watching a
third-party iOS remote (over Apple's Bluetooth logging), testing from nRF Connect and a Mac, and comparing with the
community DUML dissectors in [dji-firmware-tools](https://github.com/o-gs/dji-firmware-tools). A camera firmware
update could change any of it.

## Not the documented protocol

DJI publishes a remote protocol (the "R SDK", frames starting with `0xAA`, used by the Osmo GPS Bluetooth Remote)
in [Osmo-GPS-Controller-Demo](https://github.com/dji-sdk/Osmo-GPS-Controller-Demo). It covers the Osmo Action 4,
5 Pro and 6 and the Osmo 360; for the Nano it says "Not supported yet". The Nano advertises `0x80` where supported
cameras advertise `0xFA`, and ignores R SDK frames.

It speaks **DUML** (frames starting with `0x55`), DJI's internal protocol, over the same GATT service:

| UUID | Use |
|---|---|
| `FFF0` | Service |
| `FFF5` | Remote → camera (write without response) |
| `FFF4` | Camera → remote (notifications) |
| `FFF3`, `FFF7` | Notifications enabled by the iOS remote; nothing seen on them |

## DUML frame

```
[0x55][Len:10 bits | Ver:6 bits][CRC8][Src][Dst][Seq:2][CmdType][CmdSet][CmdId][payload][CRC16:2]
```

Little-endian. CRC8 over bytes 0-2 (seed `0x77`), CRC16 over everything before it (seed `0x3692`), both reflected
(polynomials `0x8C` and `0x8408`). Version 1: byte 2 is `0x04 | (len >> 8)`. `CmdType` `0x40` is a request, `0xC0`
a response. Both CRCs matched all 2,141 frames in the captures.

Addresses seen: `0x02` the remote (app), `0x01` camera, `0x05` battery, `0x07` connection, `0xF0` broadcast,
`0x28`, `0x48`, `0x88`, `0x1C` other modules.

## Session

`source/CameraLink.mc` does what the iOS remote did:

1. Enable notifications on `FFF3`, `FFF4`, `FFF5`, `FFF7`.
2. `00/2B 04 00` to `0xF0` (hello).
3. `07/45` to `0x07` (connect): `0x20`, a 32-character remote id, the name length, a 4-character name. **The name is
   the verification code the camera shows** ("Connection request"). Reply `00 01`: known remote; `00 02`: the camera
   asks on its screen. The remote id is kept so the camera remembers it.
4. `00/2B 01 01` to `0xF0` every second (keep-alive).
5. Answer the camera's `00/81` request with a fixed 62-byte payload (`00 'A' 'P' 'P'`, `02` at 41, `02 08` at 50)
   and echo its `00/74` request.

## Commands

| Command | Direction | Payload | Notes |
|---|---|---|---|
| `02/02` | → camera | `01` start, `00` stop | Reply `00` accepted, `DF` refused (e.g. already stopping) |
| `02/80` | camera → | status, twice a second | Byte 0: `01` idle, `41` starting, `81` recording, `C1` stopping (saving) |
| `02/71` | → camera | none | SDcard Info Get. Reply bytes 6-9: free storage in MB |
| `0d/02` | battery → | push | Bytes 1-4 voltage (mV), 5-8 current (mA, positive while charging), byte 20 percentage |
| `02/84` | camera → | push after a clip | Recording name |

Answered `e0` (not supported): `02/76` power info, `02/59` GPS get, `02/11`, `0d/01`, `0d/03`, `0d/06`, the R SDK GPS
push `00/17`, `00/53` Push Gps Info and the R SDK key report `00/11` (highlight on the Action line). DJI lists no GPS
or highlight feature for the Nano either.

DJI Mimo only uses Bluetooth to switch the camera's Wi-Fi on (`07/48`) and read its network name and password
(`07/07`, `07/0e`); everything else goes over Wi-Fi.

## Connect IQ limits

- **20-byte writes** (no long writes, no MTU request): frames are split into 20-byte writes; the Nano rebuilds them.
- **20-byte notifications**: Connect IQ only delivers the first 20 bytes of each notification, i.e. the 11-byte
  header and 9 payload bytes. `Duml.parseNotification` accepts such cut frames when the header CRC8 checks out. This
  is why the battery percentage (byte 20 of `0d/02`) is out of reach and the field estimates it from the voltage.
- **Scan results** on the Edge 540 expose neither the manufacturer data nor the service UUID for the Nano: it is
  matched by its advertised name (`OsmoNano-...`).
- **Data fields** cannot use timers or read buttons: `compute()` (once a second) drives the keep-alive, and the Lap
  button (`onTimerLap`) is the control. Lap and `compute` stop reaching the field only while the activity is paused.

## Mac test bench

`tools/nanoprobe.py` (Python 3 with `bleak`) runs the same session from a Mac, which negotiates full-size packets,
and sends queries, printing complete replies. Run it from a terminal that has Bluetooth permission in macOS settings.
