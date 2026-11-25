# EdgeCam (prototype)

Minimal Connect IQ app to check whether a **Garmin Edge 540** can control a **DJI Osmo** camera
(target: Osmo Nano) over Bluetooth LE, using DJI's published remote protocol.

Scope of this prototype: scan, connect, pair, start/stop recording, and show what the camera reports.
No data field, no GPS push, no markers yet.

## Why it might work

- The Osmo Nano advertises DJI's manufacturer id (`0x08AA`) and service `FFF0`, with `FFF4` (notify)
  and `FFF5` (write without response): the same layout DJI's remote protocol uses on the Osmo Action line.
- DJI's own docs still list the Nano as "not supported yet", and its advert byte 2 is `0x80` instead of
  the documented `0xFA`. So this filters on `0x08AA` + `FFF0` only.

## Build

1. Install the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) with the SDK Manager and
   download the **Edge 540** device.
2. Install the **Monkey C** extension for VS Code, then run *Monkey C: Generate a Developer Key* once.
3. Build:

   ```sh
   monkeyc -d edge540 -f monkey.jungle -o bin/edgecam.prg -y /path/to/developer_key.der
   ```

4. Unit tests (protocol frames against DJI's reference bytes), in the simulator:

   ```sh
   monkeyc -d edge540 -f monkey.jungle -o bin/edgecam-test.prg -y /path/to/developer_key.der --unit-test
   connectiq &
   monkeydo bin/edgecam-test.prg edge540 -t
   ```

The simulator cannot talk to the camera: the Bluetooth part only runs on the real Edge.

## Install on the Edge 540

Connect the Edge over USB (on macOS use [OpenMTP](https://openmtp.ganeshrvel.com/)) and copy
`bin/edgecam.prg` into `Garmin/Apps/`. Unplug; the app shows up under Connect IQ apps.

## Test run

1. Close DJI Mimo and Multicam on the phone so nothing else is connected to the camera.
2. Turn the camera on, open EdgeCam on the Edge.
3. It scans, connects and shows `Check camera: code NNNN`. Accept on the camera if it asks.
4. When it shows `READY`, press **ENTER** to start recording, again to stop.
5. If the link drops, press **ENTER** to scan again.

Write down what the screen shows at each step, especially:

- `Adv ...`: the advert bytes;
- `Model 0x....`: the model id the camera reports (unknown for the Nano so far);
- the log lines at the bottom (write status, replies, errors).

Logs also go to `Garmin/Apps/Logs/EDGECAM.TXT` if you create that empty file before running.

## Known risks

- Connect IQ writes at most 20 bytes per write, so frames (the connection request is 51 bytes) are sent
  in chunks. The camera should rebuild them, but that is unproven on the Nano.
- `FFF5` is write-without-response; if the Edge never calls back after such writes, a 1 s watchdog
  moves on to the next chunk.

## Credits and license

The protocol code is ported from [BiciCAM](https://github.com/apradoperez/bicicam) (MIT, BiciLAB Factory SL,
based on Horst Tellioglu's Kamerad), which follows DJI's
[Osmo-GPS-Controller-Demo](https://github.com/dji-sdk/Osmo-GPS-Controller-Demo). MIT license, see `LICENSE`.

DJI and Osmo are trademarks of their owners. Not affiliated with or endorsed by DJI or Garmin.
