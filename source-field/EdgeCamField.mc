// Data field: shows the camera state and toggles recording with the Lap button.
// Data fields cannot read buttons on the Edge 540 nor use timers, so Lap (onTimerLap) is the control
// and compute(), called once per second, drives the link's keep-alive.

import Toybox.Application;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
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
    // Colours from BiciCAM: the background says the state at a glance. Red records, navy is ready,
    // light grey (the tally light off) has no camera, amber asks for attention. Text is white on navy
    // and red, navy on light grey and amber (light grey keeps "no camera" apart from red in the sun).
    const NAVY = 0x1F2555;
    const RED = 0xD7261E;
    const GREY = 0xCFD5D9;
    const AMBER = 0xF59300;
    const WHITE = 0xFFFFFF;

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

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var background = GREY;
        var main = "CAM";
        var sub = _link.state;
        var showData = false;
        var dot = false;
        var now = System.getTimer();

        if (_link.pending != null) {
            // Sent, waiting for the camera to confirm: amber, as BiciCAM does for "wait"
            background = AMBER;
            main = _link.pending == :start ? "REC..." : "STOP...";
            sub = "Waiting for camera";
        } else if (_link.refused != null && now < _link.refusedUntil) {
            background = AMBER;
            main = "BUSY";
            sub = _link.refused;
        } else if (_link.recording) {
            background = RED;
            var secs = _link.recordingSeconds();
            main = secs != null ? (secs / 60).format("%02d") + ":" + (secs % 60).format("%02d") : "REC";
            // Tally dot blinking once a second, as on the camera
            dot = secs == null || secs % 2 == 0;
            showData = true;
        } else if (_link.connected) {
            background = NAVY;
            main = "REC";
            showData = true;
        } else if (_link.phase == CameraLink.PAIRING) {
            background = AMBER;
            main = _link.verifyCode != null ? _link.verifyCode.toString() : "PAIR";
            sub = "Accept on camera";
        } else if (_link.phase == CameraLink.FAILED) {
            background = AMBER;
        }
        var ink = (background == GREY || background == AMBER) ? NAVY : WHITE;
        dc.setColor(ink, background);
        dc.clear();

        if (!showData) {
            layoutColumn(dc, 0, 0, w, h, [[:text, main, ink, true], [:text, sub, ink, false]]);
            return;
        }

        var battery = _link.charging() ? "CHG" : (_link.batteryPercent() != null ? "~" + _link.batteryPercent() + "%" : "--%");
        var storage = _link.storageText() != null ? _link.storageText() : "--";
        var batteryColor = colorForBattery(_link.charging() ? null : _link.batteryPercent(), background);
        var mainRow = [:main, main, ink, dot];
        var batteryRow = [:icon, battery, batteryColor, :battery, _link.batteryPercent()];
        var storageRow = [:icon, storage, ink, :card, null];

        if (h > w * 3 / 4) {
            // Tall slot: three rows
            layoutColumn(dc, 0, 0, w, h, [mainRow, batteryRow, storageRow]);
        } else {
            // Normal or wide slot: REC on the left, battery over storage on the right, like BiciCAM
            var split = w > h * 2 ? w / 2 : w * 3 / 5;
            layoutColumn(dc, 0, 0, split, h, [mainRow]);
            layoutColumn(dc, split, 0, w - split, h, [batteryRow, storageRow]);
        }
    }

    // Stacks rows in a box: the first row may take up to 55 % of the height, the rest share what is
    // left, each row keeps only the height of its font, and the spare height is spread evenly.
    hidden function layoutColumn(dc, x, y, w, h, rows) {
        var n = rows.size();
        var fonts = new [n];
        var heights = new [n];
        var used = 0;
        for (var i = 0; i < n; i++) {
            var maxH = n == 1 ? h : (i == 0 ? h * 55 / 100 : (h * 45 / 100) / (n - 1));
            var r = rows[i];
            var font = null;
            if (r[0] == :main) {
                font = fit(dc, r[1], fontsFor(r[1]), w - 8, maxH * 80 / 100);
            } else if (r[0] == :icon) {
                font = fit(dc, r[1], fontsFor(r[1]), (w - 8) * 60 / 100, maxH);
            } else {
                font = fit(dc, r[1], r[3] ? fontsFor(r[1]) : [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY], w - 8, maxH);
            }
            if (font == null) {
                font = Graphics.FONT_XTINY;
            }
            fonts[i] = font;
            heights[i] = rowHeight(dc, r, font);
            used += heights[i];
        }
        var gap = (h - used) / (n + 1);
        if (gap < 0) {
            gap = 0;
        }
        var top = y + gap;
        for (var i = 0; i < n; i++) {
            drawRow(dc, x, top, w, rows[i], fonts[i]);
            top += heights[i] + gap;
        }
    }

    // The main row adds the tally dot above the text, with a clear gap between them
    hidden function rowHeight(dc, row, font) {
        var th = dc.getFontHeight(font);
        if (row[0] == :main) {
            return th + dotRadius(th) * 2 + dotGap(th);
        }
        return th;
    }

    hidden function dotRadius(textH) {
        var r = textH / 9;
        return r < 4 ? 4 : r;
    }

    hidden function dotGap(textH) {
        var g = textH / 5;
        return g < 6 ? 6 : g;
    }

    hidden function drawRow(dc, x, top, w, row, font) {
        var th = dc.getFontHeight(font);
        if (row[0] == :main) {
            var r = dotRadius(th);
            dc.setColor(row[2], Graphics.COLOR_TRANSPARENT);
            // Filled dot: recording (blinking); ring: ready
            if (row[3]) {
                dc.fillCircle(x + w / 2, top + r, r);
            } else {
                dc.setPenWidth(2);
                dc.drawCircle(x + w / 2, top + r, r);
                dc.setPenWidth(1);
            }
            dc.drawText(x + w / 2, top + r * 2 + dotGap(th), font, row[1], Graphics.TEXT_JUSTIFY_CENTER);
        } else if (row[0] == :icon) {
            drawWithIcon(dc, x, top, w, th, row[1], row[2], row[3], row[4], font);
        } else {
            dc.setColor(row[2], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w / 2, top, font, row[1], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // A value with a small battery or card drawing in front, sized to the text and centred in its box
    hidden function drawWithIcon(dc, x, y, w, h, text, color, icon, level, font) {
        var iconH = h * 55 / 100;
        var iconW = icon == :battery ? iconH * 7 / 4 : iconH * 3 / 4;
        var gap = iconH / 2;
        var tw = dc.getTextWidthInPixels(text, font);
        var left = x + (w - iconW - gap - tw) / 2;
        var iy = y + (h - iconH) / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        if (icon == :battery) {
            var nub = iconH / 6 + 1;
            var bodyW = iconW - nub;
            dc.drawRectangle(left, iy, bodyW, iconH);
            dc.fillRectangle(left + bodyW, iy + iconH / 3, nub, iconH / 3);
            if (level != null) {
                var fillW = (bodyW - 6) * (level > 100 ? 100 : level) / 100;
                dc.fillRectangle(left + 3, iy + 3, fillW, iconH - 6);
            }
        } else {
            // SD card: rectangle with a clipped corner
            var c = iconW / 3;
            dc.drawLine(left + c, iy, left + iconW, iy);
            dc.drawLine(left + iconW, iy, left + iconW, iy + iconH);
            dc.drawLine(left + iconW, iy + iconH, left, iy + iconH);
            dc.drawLine(left, iy + iconH, left, iy + c);
            dc.drawLine(left, iy + c, left + c, iy);
        }
        dc.setPenWidth(1);
        dc.drawText(left + iconW + gap, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Battery colour as in BiciCAM: green from 30 %, yellow 15-29 %, red below; on the red background
    // light tones and no red, so the percentage stays readable while recording. Unknown or charging: ink.
    hidden function colorForBattery(percent, background) {
        var ink = (background == GREY || background == AMBER) ? NAVY : WHITE;
        if (percent == null) {
            return ink;
        }
        if (background == RED) {
            return percent >= 30 ? 0xC8F7C5 : 0xFFF59D;
        }
        if (percent >= 30) {
            return background == NAVY ? 0x5BD46A : 0x1B7A2E;
        }
        if (percent >= 15) {
            return background == NAVY ? 0xFFD54F : 0x8A6D00;
        }
        return background == NAVY ? 0xFF6B6B : 0xB00020;
    }

    // Number fonts for digits (timer, code, percentages), text fonts otherwise
    hidden function fontsFor(text) {
        return isNumeric(text)
            ? [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD, Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY]
            : [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
    }

    // First font in the list whose rendering of text fits in maxW x maxH, or null
    hidden function fit(dc, text, fonts, maxW, maxH) {
        for (var i = 0; i < fonts.size(); i++) {
            var size = dc.getTextDimensions(text, fonts[i]);
            if (size[0] <= maxW && size[1] <= maxH) {
                return fonts[i];
            }
        }
        return null;
    }

    // Digits and ':' only, which the number fonts can draw
    hidden function isNumeric(text) {
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if (!((c >= '0' && c <= '9') || c == ':')) {
                return false;
            }
        }
        return chars.size() > 0;
    }
}
