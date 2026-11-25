# EdgeCam

Control a **DJI Osmo Nano** from a **Garmin Edge**: a data field that starts and stops recording with the Lap button,
shows the camera's battery and free storage, warns you when something goes wrong and records in the activity when
each clip was shot.

Free and open source. **Beta**: tested with one Osmo Nano and an Edge 540, not yet on many rides.

[Leer en español](README.es.md)

## What you need

- A **DJI Osmo Nano**. Other DJI cameras are not tested.
- A **Garmin Edge 540 / 540 Solar**, the tested one. It is also built for the Edge 840, 550, 850, 1040 and 1050, only
  tried in the simulator on those.

## Install

For now it is installed by hand: it is not in the Connect IQ Store yet.

1. Download the file for your Edge from the [releases page](../../releases/latest):
   `EdgeCam-edge540.prg` (Edge 540 / 540 Solar), `EdgeCam-edge840.prg`, `EdgeCam-edge550.prg`,
   `EdgeCam-edge850.prg`, `EdgeCam-edge1040.prg` (1040 / 1040 Solar) or `EdgeCam-edge1050.prg`.
2. Connect the Edge to a computer over USB.
   - On Windows it shows up as a device.
   - On a Mac you need an MTP tool such as [OpenMTP](https://openmtp.ganeshrvel.com/).
3. Copy that file into `Garmin/Apps/` on the Edge.
4. Unplug the Edge. The field is listed with the Connect IQ fields.

## Set up

1. **Add the field** to a data screen: *Activity Profiles → your profile → Data Screens → pick a field → Connect IQ →
   EdgeCam*. The bigger the slot, the easier it is to read.
2. **Allow its alerts**: in the same profile, *Alerts* → enable the Connect IQ / EdgeCam alerts. Without this the
   field cannot warn you.
3. **Pair the camera**: close DJI Mimo (and any other app using the camera) on your phone, switch the Nano on and go
   to the field's screen. The field turns amber with a **4-digit code** and the Nano shows a "Connection request" with
   the same code: tap **Accept**. Only the first time.

## Use

**Start the activity** and press **Lap**: the Nano starts recording. **Lap** again: it stops. Each press also marks
a lap in the activity.

The colour says the state:

| Colour | Means |
|---|---|
| Navy | Ready, with the camera's battery and free storage |
| Red | Recording, with the counter and a blinking tally dot |
| Amber | Something to do: accept the code on the camera, waiting for the camera to confirm (*REC…* / *STOP…*), or the camera is not responding (*No signal*) |
| Light grey | Looking for or connecting to the camera |

Full-screen **alerts** (if allowed):

- Recording stopped: the camera stopped without you stopping it, because of heat, full storage or its own button.
- Camera lost while recording, or camera not responding.
- Camera battery at 20 % and 10 %.
- Camera storage almost full (less than 2 GB).

**Stops**: with auto-pause, traffic lights leave the camera as it was. If the activity stays paused for **more than
2 minutes**, the field stops the camera, and it always stops it when the activity is saved or discarded. Change the
time in the **Garmin Connect** app (your Edge → Connect IQ → EdgeCam → Settings): never, 1, 2, 5 or 10 minutes.

**Finding each video on the route**: the field records in the activity, every second, whether the camera was
recording and which clip it was. Garmin Connect shows them as *Camera recording* and *Camera clip* charts; clip 3 is
the third recorded stretch.

## Limits

- **Lap only reaches the field while the activity runs**: not before starting it, not while paused. At a stop, use
  the Nano's button.
- **The battery is an estimate** from the camera's voltage (the exact percentage does not reach the Edge). It can be
  a few points off, especially while recording.
- **No GPS in the video and no highlight markers**: the Nano does not support them.
- DJI publishes no remote protocol for the Nano. EdgeCam uses one worked out by watching another app, and a camera
  update could break it.

## Privacy

EdgeCam does not use the internet or send anything anywhere: everything stays between your Edge and your camera. It
stores a random identifier on the Edge so the camera recognises it. The recording data goes into the activity file,
so it travels with it if you upload it to Garmin Connect, Strava, etc.

## Troubleshooting

- **Stuck on "Looking for camera"**: the Nano must be on, with its screen awake, and no other app connected to it.
- **No alerts**: allow them in the profile's alerts (see *Set up*).
- **To report a problem**, open an issue with your Edge model, the Nano's firmware version and what happened.

For developers: [how it is built](docs/DEVELOPMENT.md) and [what is known about the protocol](docs/PROTOCOL.md).

## Credits and license

Started from [BiciCAM](https://github.com/apradoperez/bicicam) (BiciLAB Factory SL), itself based on Horst
Tellioglu's Kamerad. Command names come from [dji-firmware-tools](https://github.com/o-gs/dji-firmware-tools). The
big font is Barlow Condensed (SIL Open Font License 1.1).

[MIT license](LICENSE). Provided without warranty.

DJI and Osmo are trademarks of their owners, as are Garmin and Edge. EdgeCam is not affiliated with or endorsed by
DJI or Garmin.
