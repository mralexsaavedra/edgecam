# EdgeCam (prototype)

Minimal Connect IQ app to check whether a **Garmin Edge 540** can control a **DJI Osmo** camera
(target: Osmo Nano) over Bluetooth LE, using DJI's published remote protocol.

Two builds share the camera code in `source/`:

- `monkey.jungle`: the **data field** (`source-field/`). Add it to a data screen; the **Lap** button starts
  and stops recording (Connect IQ data fields cannot read other buttons on the Edge 540). Navy: ready,
  red: recording, amber: accept the code on the camera, grey: looking for the camera.
- `app.jungle`: a **diagnostic app** (`source-app/`) with the state and a log on screen; ENTER toggles
  recording. It also carries the R SDK code for the Osmo Action line (`source-rsdk/`).

Not done yet: GPS push, markers, camera battery.

## How it talks to the Nano

The Osmo Nano ignores DJI's documented remote protocol (R SDK, frames starting with `0xAA`).
It speaks **DUML** (frames starting with `0x55`), DJI's internal protocol, over the same `FFF0` service:
`FFF5` to write, `FFF4` for notifications.

The session in `source/CameraLink.mc` mirrors a Bluetooth capture of a working iOS remote:

1. Enable notifications on `FFF3`, `FFF4`, `FFF5`, `FFF7`.
2. Send `00/2B 04 00` (hello) and `07/45` (connect: a 32-char remote id and a short name).
3. Send `00/2B 01 01` every second (keep-alive).
4. Answer the camera's `00/81` request with a fixed payload and echo its `00/74` request.
5. Record with `02/02 01`, stop with `02/02 00` (to the camera, address `0x01`).
6. The camera pushes `02/80` status twice a second; bit 7 of the first byte is set while recording.

On the Edge 540 the Nano is matched by its advertised name (`OsmoNano-...`): Connect IQ does not expose
its manufacturer data or service uuid in the scan result.

The R SDK code for the Osmo Action line (`source/DjiProtocol.mc`) is kept for later.

## Build

1. Install the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) with the SDK Manager and
   download the **Edge 540** device.
2. Install the **Monkey C** extension for VS Code, then run *Monkey C: Generate a Developer Key* once.
3. Build:

   ```sh
   monkeyc -d edge540 -f monkey.jungle -o bin/edgecam-field.prg -y /path/to/developer_key.der
   monkeyc -d edge540 -f app.jungle -o bin/edgecam-app.prg -y /path/to/developer_key.der
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
