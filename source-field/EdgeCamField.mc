// Data field: shows the camera state and toggles recording with the Lap button.
// Data fields cannot read buttons on the Edge 540 nor use timers, so Lap (onTimerLap) is the control
// and compute(), called once per second, drives the link's keep-alive.

import Toybox.Application;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class EdgeCamFieldApp extends Application.AppBase {
    hidden var _link;

    function initialize() {
        AppBase.initialize();
        _link = new CameraLink();
    }

    function onStart(state) {
        _link.start();
    }

    function onStop(state) {
        _link.stop();
    }

    function getInitialView() {
        return [new EdgeCamField(_link)];
    }
}

class EdgeCamField extends WatchUi.DataField {
    // Colours: navy ready, red recording, amber needs attention, grey not available
    const NAVY = 0x14244A;
    const RED = 0xC62828;
    const AMBER = 0xE0A000;
    const GREY = 0x555555;

    hidden var _link;
    // Written to the activity's FIT file so each clip can be placed on the route afterwards:
    // per second, whether the camera records and which clip it is (0 when not recording),
    // and in the summary how many clips were recorded.
    hidden var _recField;
    hidden var _clipField;
    hidden var _clipsField;
    hidden var _clips = 0;
    hidden var _wasRecording = false;

    function initialize(link) {
        DataField.initialize();
        _link = link;
        _recField = createField("camera_recording", 0, FitContributor.DATA_TYPE_UINT8,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "on/off" });
        _clipField = createField("camera_clip", 1, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "clip" });
        _clipsField = createField("camera_clips", 2, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "clip" });
        _recField.setData(0);
        _clipField.setData(0);
        _clipsField.setData(0);
    }

    function compute(info) {
        _link.tick();
        var recording = _link.recording;
        if (recording && !_wasRecording) {
            _clips++;
            _clipsField.setData(_clips);
        }
        _wasRecording = recording;
        _recField.setData(recording ? 1 : 0);
        _clipField.setData(recording ? _clips : 0);
        return null;
    }

    function onTimerLap() {
        _link.toggleRecord();
    }

    // Joins the known parts with " | ", skipping unknown (null) ones
    hidden function join(parts) {
        var text = "";
        for (var i = 0; i < parts.size(); i++) {
            if (parts[i] != null) {
                text += (text.length() > 0 ? " | " : "") + parts[i];
            }
        }
        return text;
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var background = GREY;
        var title = "CAM";
        var detail = _link.state;

        if (_link.recording) {
            background = RED;
            var secs = _link.recordingSeconds();
            title = secs != null ? (secs / 60).format("%02d") + ":" + (secs % 60).format("%02d") : "REC";
            detail = join(["REC", _link.batteryText()]);
        } else if (_link.connected) {
            background = NAVY;
            title = "READY";
            detail = join([_link.batteryText(), _link.storageText()]);
            if (detail.length() == 0) {
                detail = "Lap to record";
            }
        } else if (_link.phase == CameraLink.PAIRING) {
            background = AMBER;
            title = _link.verifyCode != null ? _link.verifyCode.toString() : "PAIR";
            detail = "Accept on camera";
        } else if (_link.phase == CameraLink.FAILED) {
            background = AMBER;
            title = "CAM";
        }

        dc.setColor(Graphics.COLOR_WHITE, background);
        dc.clear();
        var titleFont = h >= 90 ? Graphics.FONT_LARGE : Graphics.FONT_MEDIUM;
        var detailFont = Graphics.FONT_XTINY;
        var titleH = dc.getFontHeight(titleFont);
        var detailH = dc.getFontHeight(detailFont);
        var showDetail = h >= titleH + detailH + 4;
        var top = showDetail ? (h - titleH - detailH) / 2 : (h - titleH) / 2;
        dc.drawText(w / 2, top, titleFont, title, Graphics.TEXT_JUSTIFY_CENTER);
        if (showDetail) {
            dc.drawText(w / 2, top + titleH, detailFont, detail, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
