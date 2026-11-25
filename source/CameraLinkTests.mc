// Camera events raised by the link, fed with camera frames as they arrive over BLE.

import Toybox.Lang;
import Toybox.Test;

function statusFrame(byte0) {
    return Duml.encode(0x01, 0x02, 0x1000, 0x00, 0x02, 0x80, [byte0, 0x02, 0x80, 0x00, 0x01, 0x01, 0xC0, 0x00, 0x00]b);
}

// 0d/02 push from the battery (0x05): index, voltage mV and current mA, little-endian
function batteryFrame(mv, ma) {
    var p = new [9]b;
    p[1] = mv & 0xFF;
    p[2] = (mv >> 8) & 0xFF;
    p[5] = ma & 0xFF;
    p[6] = (ma >> 8) & 0xFF;
    p[7] = (ma >> 16) & 0xFF;
    p[8] = (ma >> 24) & 0xFF;
    return Duml.encode(0x05, 0x02, 0x1001, 0x00, 0x0D, 0x02, p);
}

(:test)
function linkAnnouncesRecordingStoppedByTheCamera(logger) {
    var link = new CameraLink();
    link.onCharacteristicChanged(null, statusFrame(0x81));
    var wasRecording = link.recording;
    link.onCharacteristicChanged(null, statusFrame(0xC1));
    return wasRecording && !link.recording && link.takeEvent() == :stopped && link.takeEvent() == null;
}

(:test)
function linkAnnouncesLowBatteryOnceAt20AndAt10(logger) {
    var link = new CameraLink();
    link.onCharacteristicChanged(null, batteryFrame(3670, -150));
    var at20 = link.takeEvent();
    link.onCharacteristicChanged(null, batteryFrame(3665, -150));
    var again = link.takeEvent();
    link.onCharacteristicChanged(null, batteryFrame(3560, -150));
    var at10 = link.takeEvent();
    return at20 == :battery20 && again == null && at10 == :battery10;
}

(:test)
function linkStaysQuietWhileCharging(logger) {
    var link = new CameraLink();
    link.onCharacteristicChanged(null, batteryFrame(3560, 400));
    return link.takeEvent() == null && link.charging();
}
