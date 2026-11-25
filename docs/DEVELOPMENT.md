# Development

## Layout

| Path | What |
|---|---|
| `source/` | Shared: DUML protocol (`DjiDuml.mc`), BLE link (`CameraLink.mc`), their tests |
| `source-field/` | The data field (the product) |
| `source-app/` | EdgeCam Debug, a full-screen app with the link state and a log; ENTER records/stops |
| `source-rsdk/` | DJI's documented R SDK protocol for the Osmo Action line, ported from BiciCAM. Built into the debug app only; **untested with any camera** |
| `resources-field/`, `resources-field-spa/` | Field strings (English, Spanish), FIT charts, settings, big font |
| `tools/` | `mkfont.py` (big font), `mtpsend.c` (copy to the Edge), `nanoprobe.py` (Mac test bench) |
| `docs/PROTOCOL.md` | What is known about the Nano and DUML |

## Build

1. Install the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) with the SDK Manager and download the
   devices you build for (only those: all devices take about 1.5 GB).
2. Create a developer key once (the Monkey C extension for VS Code has *Generate a Developer Key*, or
   `openssl genrsa -out key.pem 4096 && openssl pkcs8 -topk8 -inform PEM -outform DER -in key.pem -out key.der -nocrypt`).
   Keep it: the Edge only updates an app signed with the same key.
3. Build (the data field supports edge540, edge840, edge550, edge850, edge1040 and edge1050; the debug app only
   edge540). Use `-d <device>` per model; `monkeyc -e` exports one `.iq` package with all of them for the
   Connect IQ Store:

   ```sh
   monkeyc -d edge540 -f monkey.jungle -o bin/edgecam-field.prg -y key.der   # data field
   monkeyc -d edge540 -f app.jungle -o bin/edgecam-app.prg -y key.der      # debug app
   ```

## Tests

Unit tests run in the simulator (DUML frames against bytes captured from a working remote, the R SDK against DJI's
reference frames, the link's alerts, the auto-stop rule):

```sh
monkeyc -d edge540 -f monkey.jungle -o bin/edgecam-field-test.prg -y key.der --unit-test
connectiq &
monkeydo bin/edgecam-field-test.prg edge540 -t
```

The simulator has no Bluetooth to the camera: anything involving the camera has to be tried on an Edge.

## Install on an Edge

Copy the `.prg` into `Garmin/Apps/` on the Edge (USB, MTP). On macOS without a file manager for MTP:

```sh
brew install libmtp
cc -o mtpsend tools/mtpsend.c $(pkg-config --cflags --libs libmtp)
mtp-folders                      # note the id of Garmin/Apps
mtp-files                        # if EDGECAMF.PRG is already in Apps: mtp-delfile -n <its id>
./mtpsend bin/edgecam-field.prg EDGECAMF.PRG <apps id>
```

`mtp-sendfile` cannot resolve Garmin's folder paths, hence `mtpsend`, which takes the folder id. The Edge refuses a
second file with the same name in `Apps` until it has installed the first one (on unplugging).

Logs: create an empty `Garmin/Apps/LOGS/EDGECAMF.TXT` (field) or `EDGECAM.TXT` (debug app) and the Edge appends
`System.println` output to it.

## Big text font

Connect IQ's system text fonts stop at `FONT_LARGE`, smaller than the number fonts, so the field carries Barlow
Condensed Bold (SIL Open Font License 1.1, `licenses/OFL-BarlowCondensed.txt`) as bitmap fonts with only the letters
it uses. To rebuild them after changing `GLYPHS` in `tools/mkfont.py`:

```sh
python3 -m pip install pillow
python3 tools/mkfont.py BarlowCondensed-Bold.ttf resources-field/fonts
```
