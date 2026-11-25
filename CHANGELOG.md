# Changelog

## 0.1.0 (beta)

First public version. Tested with a DJI Osmo Nano and a Garmin Edge 540; built for the Edge 840, 550, 850, 1040 and
1050 and only tried in the simulator on those.

- Data field that starts and stops the Osmo Nano's recording with the Lap button.
- Pairing with a 4-digit code shown on the field and on the camera.
- State colours: navy ready, red recording (counter and blinking tally dot), amber when something is needed,
  light grey while looking for the camera.
- Camera battery (estimated from its voltage, with a charging bolt) and free storage.
- Alerts: recording stopped by the camera, camera lost or not responding while recording, battery at 20 % and 10 %,
  storage below 2 GB. "No signal" state when the camera goes silent while recording.
- Stops the camera after a long pause (2 minutes by default, set in the Garmin Connect app) and when the activity is
  saved or discarded.
- Records in the activity FIT file whether the camera was recording and the clip number, every second.
- Reconnects on its own when the camera is lost.
- English and Spanish.

Versión 0.1.0 (beta): primera versión pública. Probada con una DJI Osmo Nano y un Garmin Edge 540; compilada para
el Edge 840, 550, 850, 1040 y 1050, solo probada en el simulador en esos. Graba y para con Lap, enseña la batería y el
espacio de la cámara, avisa si algo va mal, para la cámara en pausas largas y al terminar, y apunta los clips en la
actividad.
