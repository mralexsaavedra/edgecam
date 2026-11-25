import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class EdgeCamApp extends Application.AppBase {
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
        return [new MainView(_link), new MainDelegate(_link)];
    }
}

class MainView extends WatchUi.View {
    hidden var _link;

    function initialize(link) {
        View.initialize();
        _link = link;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var y = 4;

        var headline = "EdgeCam";
        var color = Graphics.COLOR_WHITE;
        if (_link.connected) {
            headline = _link.recording ? "REC" : "READY";
            color = _link.recording ? Graphics.COLOR_RED : Graphics.COLOR_GREEN;
        }
        y = line(dc, y, Graphics.FONT_MEDIUM, headline, color);
        y = line(dc, y, Graphics.FONT_XTINY, _link.state, Graphics.COLOR_WHITE);
        y += 4;

        if (_link.cameraName != null) {
            y = line(dc, y, Graphics.FONT_XTINY, _link.cameraName, Graphics.COLOR_LT_GRAY);
        }
        if (_link.advertHex != null) {
            y = line(dc, y, Graphics.FONT_XTINY, "Adv " + _link.advertHex, Graphics.COLOR_LT_GRAY);
        }
        if (_link.verifyCode != null) {
            y = line(dc, y, Graphics.FONT_XTINY, "Code " + _link.verifyCode, Graphics.COLOR_LT_GRAY);
        }
        y = line(dc, y, Graphics.FONT_XTINY, "Model " + _link.modelHex(), Graphics.COLOR_LT_GRAY);
        if (_link.battery != null) {
            y = line(dc, y, Graphics.FONT_XTINY, "Battery " + _link.battery + "%  mode 0x" + _link.mode.format("%02X"), Graphics.COLOR_LT_GRAY);
        }

        y += 6;
        for (var i = 0; i < _link.logLines.size(); i++) {
            y = line(dc, y, Graphics.FONT_XTINY, _link.logLines[i], Graphics.COLOR_DK_GRAY);
        }
    }

    hidden function line(dc, y, font, text, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(4, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
        return y + dc.getFontHeight(font);
    }
}

class MainDelegate extends WatchUi.BehaviorDelegate {
    hidden var _link;

    function initialize(link) {
        BehaviorDelegate.initialize();
        _link = link;
    }

    // ENTER: record/stop when connected, scan again when idle
    function onSelect() {
        if (_link.connected) {
            _link.toggleRecord();
        } else if (_link.isIdle()) {
            _link.startScan();
        }
        return true;
    }
}
