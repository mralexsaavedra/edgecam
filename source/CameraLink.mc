// BLE link with a DJI Osmo Nano over DUML: scan, connect, session, status and record control.
// The session mirrors what a working iOS remote did in a Bluetooth capture:
// enable notifications on FFF3/FFF4/FFF5/FFF7, send 00/2B hello, 07/45 connect, keep-alive every
// second, answer the camera's 00/81 and 00/74 requests, and use 02/02 to start/stop recording.
//
// Connect IQ limits that shape this class:
// - only one BLE request (write, descriptor write) may be outstanding at a time;
// - a characteristic write is at most 20 bytes, so frames are split and sent one chunk at a time;
// - notifications arrive cut to 20 bytes (see Duml.parseNotification);
// - data fields cannot use timers: the owner calls tick() regularly (the field once per second).

import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

class CameraLink extends BluetoothLowEnergy.BleDelegate {
    const CHUNK = 20;
    const WRITE_ACK_TIMEOUT_MS = 1000;
    const KEEPALIVE_MS = 1000;
    const RESCAN_AFTER_MS = 3000;
    // After the camera accepts a start/stop, its status push can lag behind for a moment
    const STATUS_HOLD_MS = 1500;
    const LOG_LINES = 10;
    const STORAGE_POLL_MS = 30000;

    // Phases, for the screen
    enum {
        STARTING,
        SCANNING,
        CONNECTING,
        PAIRING,
        READY,
        DISCONNECTED,
        FAILED
    }

    var phase = STARTING;
    var state = "Starting";
    var cameraName = null;
    var verifyCode = null;
    var connected = false;
    var recording = false;
    var logLines = [];
    // Camera data, null until known
    var batteryMv = null;
    var batteryMa = null;
    var freeMb = null;
    var recordingSince = null;
    // A start or stop sent and not answered yet (:start / :stop), for feedback on the screen
    var pending = null;
    // Short message when the camera refused a command, shown until refusedUntil
    var refused = null;
    var refusedUntil = 0;

    hidden var _device = null;
    hidden var _write = null;
    hidden var _cccds = [];
    hidden var _queue = [];
    hidden var _busy = false;
    hidden var _busySince = 0;
    hidden var _seq = 0;
    hidden var _remoteId;
    hidden var _scanning = false;
    hidden var _sessionStarted = false;
    hidden var _lastKeepAlive = 0;
    hidden var _lostAt = 0;
    hidden var _requestedStart = false;
    hidden var _statusHoldUntil = 0;
    hidden var _keysSeen = [];
    hidden var _lastStoragePoll = 0;
    hidden var _pendingSince = 0;

    function initialize() {
        BleDelegate.initialize();
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
        var uuids = Duml.notifyUuids();
        for (var i = 0; i < uuids.size(); i++) {
            characteristics.add({ :uuid => uuids[i], :descriptors => [BluetoothLowEnergy.cccdUuid()] });
        }
        try {
            BluetoothLowEnergy.registerProfile({ :uuid => Duml.serviceUuid(), :characteristics => characteristics });
            state = "Registering BLE profile";
        } catch (e) {
            // Seen in the simulator when the app restarts in the same session: the profile is
            // already registered, so scanning can go ahead anyway
            log("registerProfile: " + e.getErrorMessage());
            startScan();
        }
    }

    function stop() {
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
        setPhase(SCANNING, "Looking for camera");
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    function toggleRecord() {
        if (!connected) {
            log("Not connected: ignored");
            return;
        }
        _requestedStart = !recording;
        pending = _requestedStart ? :start : :stop;
        _pendingSince = System.getTimer();
        log(_requestedStart ? "Sending START" : "Sending STOP");
        send(Duml.record(nextSeq(), _requestedStart));
    }

    // Stops the camera if it records and nothing is in flight; reason goes to the log
    function stopRecording(reason) {
        if (!connected || !recording || pending != null) {
            return;
        }
        log("Auto stop: " + reason);
        _requestedStart = false;
        pending = :stop;
        _pendingSince = System.getTimer();
        send(Duml.record(nextSeq(), false));
    }

    // Keep-alive, watchdog for a write whose callback never arrives, and rescan after a lost link.
    // Call it at least once per second.
    function tick() {
        var now = System.getTimer();
        if (_sessionStarted && now - _lastKeepAlive >= KEEPALIVE_MS) {
            _lastKeepAlive = now;
            send(Duml.keepAlive(nextSeq()));
        }
        if (_busy && now - _busySince > WRITE_ACK_TIMEOUT_MS) {
            log("No write callback, continuing");
            _busy = false;
            pump();
        }
        // No answer in 3 s: drop the "waiting" state, the status push says what really happened
        if (pending != null && now - _pendingSince > 3000) {
            log("No REC reply");
            pending = null;
        }
        if (connected && (_lastStoragePoll == 0 || now - _lastStoragePoll >= STORAGE_POLL_MS)) {
            _lastStoragePoll = now;
            send(Duml.sdcardInfo(nextSeq()));
            if (freeMb == null) {
                log("Storage query sent");
            }
        }
        if (phase == DISCONNECTED && now - _lostAt > RESCAN_AFTER_MS) {
            startScan();
        }
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
            // On the Edge 540 the Nano is only recognised by its advertised name: the
            // manufacturer data and the FFF0 service uuid are not exposed in the scan result.
            var name = r.getDeviceName();
            if ((name != null && name.find("Osmo") == 0) || r.getManufacturerSpecificData(Duml.COMPANY_ID) != null) {
                onCameraFound(r, name);
                return;
            }
            r = results.next();
        }
    }

    function onConnectedStateChanged(device, connectionState) {
        if (connectionState != BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            log("Link lost");
            resetLink();
            _lostAt = System.getTimer();
            setPhase(DISCONNECTED, "Camera lost, retrying");
            return;
        }
        _device = device;
        var service = device.getService(Duml.serviceUuid());
        if (service == null) {
            fail("No FFF0 service");
            return;
        }
        _write = service.getCharacteristic(Duml.writeUuid());
        if (_write == null) {
            fail("FFF5 missing");
            return;
        }
        _cccds = [];
        var uuids = Duml.notifyUuids();
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
        var frames = Duml.parseNotification(value);
        for (var i = 0; i < frames.size(); i++) {
            handleFrame(frames[i]);
        }
    }

    // ---- Session ----

    hidden function onCameraFound(result, name) {
        _scanning = false;
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        cameraName = name != null ? name : "DJI camera";
        log("Found " + cameraName);
        setPhase(CONNECTING, "Connecting");
        try {
            _device = BluetoothLowEnergy.pairDevice(result);
            if (_device == null) {
                fail("pairDevice returned null");
            }
        } catch (e) {
            fail("pairDevice failed: " + e.getErrorMessage());
        }
    }

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

    // The camera shows the 4-char name as the verification code on its screen
    hidden function startSession() {
        _sessionStarted = true;
        _lastKeepAlive = System.getTimer();
        verifyCode = 1000 + Math.rand() % 9000;
        setPhase(PAIRING, "Accept " + verifyCode + " on camera");
        log("Hello + connect, code " + verifyCode);
        send(Duml.hello(nextSeq()));
        send(Duml.connect(nextSeq(), _remoteId, verifyCode.toString()));
    }

    hidden function handleFrame(frame) {
        if (frame.isCommand(0x02, 0x80)) {
            var wasRecording = recording;
            if (System.getTimer() >= _statusHoldUntil) {
                recording = Duml.isRecording(frame.payload);
            }
            noteRecordingChange(wasRecording);
            return;
        }
        if (frame.isCommand(0x0D, 0x02) && !frame.isResponse()) {
            batteryMv = Duml.batteryMillivolts(frame.payload);
            batteryMa = Duml.batteryMilliamps(frame.payload);
            return;
        }
        if (frame.isResponse()) {
            if (frame.isCommand(0x07, 0x45)) {
                // 00 01: known remote; 00 02: the camera asks for confirmation on its screen
                log("Connect reply " + Duml.toHex(frame.payload));
                markConnected();
            } else if (frame.isCommand(0x02, 0x02)) {
                log("REC reply " + Duml.toHex(frame.payload));
                pending = null;
                if (frame.payload.size() > 0 && frame.payload[0] != 0x00) {
                    refused = "Camera busy";
                    refusedUntil = System.getTimer() + 3000;
                }
                // 00 means accepted: trust it until the status push catches up
                if (frame.payload.size() > 0 && frame.payload[0] == 0x00) {
                    var wasRecording = recording;
                    recording = _requestedStart;
                    _statusHoldUntil = System.getTimer() + STATUS_HOLD_MS;
                    noteRecordingChange(wasRecording);
                }
            } else if (frame.isCommand(0x02, 0x71)) {
                if (freeMb == null) {
                    log("Storage reply " + Duml.toHex(frame.payload));
                }
                var mb = Duml.freeMegabytes(frame.payload);
                if (mb != null) {
                    freeMb = mb;
                }
            } else {
                noteKey("resp " + frame.key());
            }
            return;
        }
        if (frame.isCommand(0x00, 0x81)) {
            send(Duml.answer81(frame));
        } else if (frame.isCommand(0x00, 0x74)) {
            send(Duml.echo(frame));
        } else {
            noteKey(frame.src.format("%02X") + " " + frame.key());
        }
    }

    hidden function noteRecordingChange(wasRecording) {
        if (recording == wasRecording) {
            return;
        }
        recordingSince = recording ? System.getTimer() : null;
        log(recording ? "Camera RECORDING" : "Camera stopped");
    }

    // Seconds recorded, counted by the Edge from the moment the camera confirmed it records
    function recordingSeconds() {
        return recordingSince == null ? null : (System.getTimer() - recordingSince) / 1000;
    }

    // Estimated battery percentage, or null when unknown
    function batteryPercent() {
        return batteryMv == null ? null : Duml.batteryPercent(batteryMv);
    }

    // Above 30 mA: on external power with a full battery the current wobbles around zero
    function charging() {
        return batteryMa != null && batteryMa > 30;
    }

    // "~74%", "CHG" while charging, or null when unknown
    function batteryText() {
        if (batteryMv == null) {
            return null;
        }
        if (batteryMa != null && batteryMa > 0) {
            return "CHG";
        }
        return "~" + Duml.batteryPercent(batteryMv) + "%";
    }

    // "46GB" (or "850MB" below 1 GB), or null when unknown
    function storageText() {
        if (freeMb == null) {
            return null;
        }
        return freeMb >= 1024 ? (freeMb / 1024) + "GB" : freeMb + "MB";
    }

    hidden function markConnected() {
        if (connected) {
            return;
        }
        connected = true;
        setPhase(READY, "Connected");
        log("Connected");
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

    // ---- Helpers ----

    hidden function nextSeq() {
        _seq = (_seq + 1) & 0xFFFF;
        return _seq;
    }

    hidden function setPhase(newPhase, message) {
        phase = newPhase;
        state = message;
    }

    hidden function resetLink() {
        connected = false;
        recording = false;
        _write = null;
        _cccds = [];
        _queue = [];
        _busy = false;
        _sessionStarted = false;
        _statusHoldUntil = 0;
        _lastStoragePoll = 0;
        recordingSince = null;
        pending = null;
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
        setPhase(FAILED, message);
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
