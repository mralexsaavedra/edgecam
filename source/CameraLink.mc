// BLE link with a DJI Osmo Nano over DUML: scan, connect, session, status and record control.
// The session mirrors what a working iOS remote did in a Bluetooth capture:
// enable notifications on FFF3/FFF4/FFF5/FFF7, send 00/2B hello, 07/45 connect, keep-alive every
// second, answer the camera's 00/81 and 00/74 requests, and use 02/02 to start/stop recording.
//
// Connect IQ limits that shape this class:
// - only one BLE request (write, descriptor write) may be outstanding at a time;
// - a characteristic write is at most 20 bytes, so frames are split and sent one chunk at a time.

import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class CameraLink extends BluetoothLowEnergy.BleDelegate {
    const CHUNK = 20;
    const WRITE_ACK_TIMEOUT_MS = 1000;
    const LOG_LINES = 10;
    const TICK_MS = 250;
    const KEEPALIVE_TICKS = 4;
    const NAME = "EDGE";

    // What the screen shows
    var state = "Starting";
    var cameraName = null;
    var advertHex = null;
    var verifyCode = null;
    var connected = false;
    var recording = false;
    var battery = null;
    var mode = null;
    var logLines = [];

    hidden var _device = null;
    hidden var _write = null;
    hidden var _cccds = [];
    hidden var _queue = [];
    hidden var _busy = false;
    hidden var _busySince = 0;
    hidden var _seq = 0;
    hidden var _assembler;
    hidden var _remoteId;
    hidden var _scanning = false;
    hidden var _sessionStarted = false;
    hidden var _ticks = 0;
    hidden var _timer;
    hidden var _advertsSeen = 0;
    hidden var _namesSeen = [];
    hidden var _keysSeen = [];

    function initialize() {
        BleDelegate.initialize();
        _assembler = new Duml.Assembler();
        _timer = new Timer.Timer();
        Math.srand(System.getTimer());
        _seq = Math.rand() & 0xFFFF;
        loadIdentity();
    }

    // A 32-char id for this remote, the same on every connection so the camera remembers it
    hidden function loadIdentity() {
        var id = Application.Storage.getValue("dumlId");
        if (!(id instanceof String) || id.length() != 32) {
            id = "";
            for (var i = 0; i < 16; i++) {
                id += (Math.rand() % 256).format("%02x");
            }
            Application.Storage.setValue("dumlId", id);
        }
        _remoteId = id;
    }

    function start() {
        BluetoothLowEnergy.setDelegate(self);
        var characteristics = [];
        var uuids = Nano.characteristicUuids();
        for (var i = 0; i < uuids.size(); i++) {
            characteristics.add({ :uuid => uuids[i], :descriptors => [BluetoothLowEnergy.cccdUuid()] });
        }
        try {
            BluetoothLowEnergy.registerProfile({ :uuid => Dji.serviceUuid(), :characteristics => characteristics });
            state = "Registering BLE profile";
        } catch (e) {
            // Seen in the simulator when the app restarts in the same session: the profile is
            // already registered, so scanning can go ahead anyway
            log("registerProfile: " + e.getErrorMessage());
            startScan();
        }
        _timer.start(method(:tick), TICK_MS, true);
    }

    function stop() {
        _timer.stop();
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            if (_device != null) {
                BluetoothLowEnergy.unpairDevice(_device);
            }
        } catch (e) {
            System.println("stop: " + e.getErrorMessage());
        }
    }

    function isIdle() {
        return !_scanning && !connected && _device == null;
    }

    function startScan() {
        if (_device != null) {
            try {
                BluetoothLowEnergy.unpairDevice(_device);
            } catch (e) {
                log("unpair: " + e.getErrorMessage());
            }
            _device = null;
        }
        resetLink();
        _scanning = true;
        state = "Scanning for DJI camera";
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    function toggleRecord() {
        if (!connected) {
            return;
        }
        log(recording ? "Sending STOP" : "Sending START");
        send(Duml.record(nextSeq(), !recording));
    }

    // ---- BleDelegate ----

    function onProfileRegister(uuid, status) {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            startScan();
        } else {
            fail("Profile register failed: " + status);
        }
    }

    function onScanResults(results) {
        if (!_scanning) {
            return;
        }
        var r = results.next();
        while (r != null) {
            _advertsSeen++;
            var data = r.getManufacturerSpecificData(Dji.COMPANY_ID);
            var name = r.getDeviceName();
            var byName = name != null && name.find("Osmo") == 0;
            var byService = advertisesDjiService(r);
            noteDevice(name, data != null, byService);
            // On the Edge 540 the Nano is only recognised by name: the manufacturer data and the
            // FFF0 service uuid are not exposed in the scan result.
            if (data != null || byService || byName) {
                onCameraFound(r, data != null ? data : []b);
                return;
            }
            r = results.next();
        }
        state = "Scanning (" + _advertsSeen + " adverts)";
    }

    function onConnectedStateChanged(device, connectionState) {
        if (connectionState != BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            log("Link lost");
            resetLink();
            state = "Disconnected. ENTER to scan";
            return;
        }
        _device = device;
        var service = device.getService(Dji.serviceUuid());
        if (service == null) {
            fail("No FFF0 service");
            return;
        }
        _write = service.getCharacteristic(Dji.writeUuid());
        if (_write == null) {
            fail("FFF5 missing");
            return;
        }
        // Same order as the iOS remote: FFF3, FFF4, FFF5, FFF7
        _cccds = [];
        var uuids = Nano.characteristicUuids();
        for (var i = 0; i < uuids.size(); i++) {
            var c = service.getCharacteristic(uuids[i]);
            var d = c != null ? c.getDescriptor(BluetoothLowEnergy.cccdUuid()) : null;
            if (d != null) {
                _cccds.add(d);
            }
        }
        state = "Enabling notifications";
        enableNextCccd();
    }

    function onDescriptorWrite(descriptor, status) {
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            log("CCCD write status " + status);
        }
        enableNextCccd();
    }

    function onCharacteristicWrite(characteristic, status) {
        _busy = false;
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            log("Write status " + status);
        }
        pump();
    }

    function onCharacteristicChanged(characteristic, value) {
        var frames = _assembler.feed(value);
        for (var i = 0; i < frames.size(); i++) {
            handleFrame(frames[i]);
        }
    }

    // ---- Session ----

    hidden function enableNextCccd() {
        if (_cccds.size() == 0) {
            startSession();
            return;
        }
        var d = _cccds[0];
        _cccds = _cccds.slice(1, null);
        try {
            d.requestWrite([0x01, 0x00]b);
        } catch (e) {
            log("CCCD write failed: " + e.getErrorMessage());
            enableNextCccd();
        }
    }

    hidden function startSession() {
        _sessionStarted = true;
        state = "Session: waiting for camera";
        log("Hello + connect as " + NAME);
        send(Duml.hello(nextSeq()));
        send(Duml.connect(nextSeq(), _remoteId, NAME));
    }

    hidden function handleFrame(frame) {
        var key = frame.key();
        if (frame.isCommand(0x02, 0x80)) {
            var wasRecording = recording;
            recording = Duml.isRecording(frame.payload);
            if (!connected) {
                markConnected("status");
            }
            if (recording != wasRecording) {
                log(recording ? "Camera RECORDING" : "Camera stopped");
            }
            return;
        }
        if (frame.isResponse()) {
            if (frame.isCommand(0x07, 0x45)) {
                log("Connect reply " + Dji.toHex(frame.payload));
                markConnected("connect reply");
            } else if (frame.isCommand(0x02, 0x02)) {
                log("REC reply " + Dji.toHex(frame.payload));
            } else {
                noteKey("resp " + key);
            }
            return;
        }
        if (frame.isCommand(0x00, 0x81)) {
            send(Duml.answer81(frame));
        } else if (frame.isCommand(0x00, 0x74)) {
            send(Duml.echo(frame));
        } else {
            noteKey(frame.src.format("%02X") + " " + key);
        }
    }

    hidden function markConnected(reason) {
        if (connected) {
            return;
        }
        connected = true;
        state = "Connected";
        log("Connected (" + reason + ")");
    }

    hidden function onCameraFound(result, data) {
        _scanning = false;
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        cameraName = result.getDeviceName();
        if (cameraName == null) {
            cameraName = "DJI camera";
        }
        advertHex = Dji.toHex(data);
        log("Found " + cameraName);
        state = "Connecting";
        try {
            _device = BluetoothLowEnergy.pairDevice(result);
            if (_device == null) {
                fail("pairDevice returned null");
            }
        } catch (e) {
            fail("pairDevice failed: " + e.getErrorMessage());
        }
    }

    hidden function advertisesDjiService(result) {
        var service = Dji.serviceUuid();
        var uuids = result.getServiceUuids();
        var u = uuids.next();
        while (u != null) {
            if (u.equals(service)) {
                return true;
            }
            u = uuids.next();
        }
        return false;
    }

    // ---- Writes ----

    hidden function send(frame) {
        for (var i = 0; i < frame.size(); i += CHUNK) {
            var end = i + CHUNK;
            if (end > frame.size()) {
                end = frame.size();
            }
            _queue.add(frame.slice(i, end));
        }
        pump();
    }

    hidden function pump() {
        if (_busy || _write == null || _queue.size() == 0) {
            return;
        }
        var chunk = _queue[0];
        _queue = _queue.slice(1, null);
        try {
            // FFF5 only supports write without response (WRITE_TYPE_DEFAULT)
            _write.requestWrite(chunk, { :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT });
            _busy = true;
            _busySince = System.getTimer();
        } catch (e) {
            _busy = false;
            log("Write failed: " + e.getErrorMessage());
        }
    }

    // Keep-alive, watchdog for a write whose callback never arrives, and screen refresh
    function tick() {
        _ticks++;
        if (_sessionStarted && _ticks % KEEPALIVE_TICKS == 0) {
            send(Duml.keepAlive(nextSeq()));
        }
        if (_busy && System.getTimer() - _busySince > WRITE_ACK_TIMEOUT_MS) {
            log("No write callback, continuing");
            _busy = false;
            pump();
        }
        WatchUi.requestUpdate();
    }

    // ---- Helpers ----

    hidden function nextSeq() {
        _seq = (_seq + 1) & 0xFFFF;
        return _seq;
    }

    hidden function resetLink() {
        connected = false;
        recording = false;
        battery = null;
        mode = null;
        _write = null;
        _cccds = [];
        _queue = [];
        _busy = false;
        _sessionStarted = false;
        _assembler = new Duml.Assembler();
    }

    function modelHex() {
        return "Nano (DUML)";
    }

    // Logs each new named device once, to see what the Edge actually hears
    hidden function noteDevice(name, hasDjiData, hasService) {
        if (name == null || _namesSeen.indexOf(name) >= 0 || _namesSeen.size() >= 8) {
            return;
        }
        _namesSeen.add(name);
        log("Saw " + name + (hasDjiData ? " +mfr" : "") + (hasService ? " +svc" : ""));
    }

    // Logs each new kind of camera message once
    hidden function noteKey(key) {
        if (_keysSeen.indexOf(key) >= 0) {
            return;
        }
        _keysSeen.add(key);
        log("rx " + key);
    }

    hidden function fail(message) {
        state = message;
        log(message);
    }

    hidden function log(message) {
        System.println(message);
        logLines.add(message);
        if (logLines.size() > LOG_LINES) {
            logLines = logLines.slice(logLines.size() - LOG_LINES, null);
        }
    }
}

module Nano {
    function characteristicUuids() {
        return [
            BluetoothLowEnergy.stringToUuid("0000fff3-0000-1000-8000-00805f9b34fb"),
            BluetoothLowEnergy.stringToUuid("0000fff4-0000-1000-8000-00805f9b34fb"),
            BluetoothLowEnergy.stringToUuid("0000fff5-0000-1000-8000-00805f9b34fb"),
            BluetoothLowEnergy.stringToUuid("0000fff7-0000-1000-8000-00805f9b34fb")
        ];
    }
}
