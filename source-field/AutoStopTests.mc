import Toybox.Lang;
import Toybox.Test;

(:test)
function autoStopWaitsForTheConfiguredMinutes(logger) {
    var paused = 1000;
    return !AutoStop.due(paused, paused + 119999, 2, true)
        && AutoStop.due(paused, paused + 120000, 2, true);
}

(:test)
function autoStopNeverWhenOffRunningOrNotRecording(logger) {
    var paused = 1000;
    var late = paused + 3600000;
    return !AutoStop.due(paused, late, 0, true)
        && !AutoStop.due(null, late, 2, true)
        && !AutoStop.due(paused, late, 2, false);
}
