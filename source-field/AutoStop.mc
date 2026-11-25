// When to stop the camera on its own while the activity is paused (auto-pause or Start button):
// only after a long stop, so traffic lights never cut a clip but a coffee stop does.

import Toybox.Lang;

module AutoStop {
    // minutes == 0 turns it off; pausedSince is null while the timer runs
    function due(pausedSince, now, minutes, recording) {
        if (!recording || pausedSince == null || minutes <= 0) {
            return false;
        }
        return now - pausedSince >= minutes * 60000;
    }
}
