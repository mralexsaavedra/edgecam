// BLE link with a DJI camera: scan, connect, handshake, status and record control.
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
    const LOG_LINES = 5;

    // What the screen shows
    var state = "Starting";
    var cameraName = null;
    var advertHex = null;
    var verifyCode = null;
    var cameraDeviceId = 0l;
    var connected = false;
    var recording = false;
    var battery = null;
    var mode = null;
    var logLines = [];

    hidden var _device = null;
    hidden var _write = null;
    hidden var _queue = [];
    hidden var _busy = false;
    hidden var _busySince = 0;
    hidden var _seq = 0;
    hidden var _assembler;
    hidden var _deviceId;
    hidden var _mac;
    hidden var _lastAckAt = 0;
    hidden var _scanning = false;
    hidden var _timer;

    function initialize() {
        BleDelegate.initialize();
        _assembler = new Dji.Assembler();
        _timer = new Timer.Timer();
        loadIdentity();
        Math.srand(System.getTimer());
        _seq = 1 + Math.rand() % 0x4000;
    }

    // Identity of this remote, the same on every connection so the camera remembers it.
    hidden function loadIdentity() {
        var id = Application.Storage.getValue("deviceId");
        var mac = Application.Storage.getValue("mac");
        if (!(id instanceof Number) || !(mac instanceof Array)) {
            Math.srand(System.getTimer());
            id = 0x10000000 + Math.rand() % 0x6FFFFFFF;
            mac = [];
            for (var i = 0; i < 6; i++) {
                mac.add(Math.rand() % 256);
            }
            mac[0] = (mac[0] & 0xFE) | 0x02; // locally administered, unicast
            Application.Storage.setValue("deviceId", id);
            Application.Storage.setValue("mac", mac);
        }
        _deviceId = id.toLong();
        _mac = new [6]b;
        for (var i = 0; i < 6; i++) {
            _mac[i] = mac[i];
        }
    }

    function start() {
        BluetoothLowEnergy.setDelegate(self);
        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => Dji.serviceUuid(),
                :characteristics => [
                    { :uuid => Dji.notifyUuid(), :descriptors => [BluetoothLowEnergy.cccdUuid()] },
                    { :uuid => Dji.writeUuid() }
                ]
            });
            state = "Registering BLE profile";
        } catch (e) {
            fail("registerProfile failed: " + e.getErrorMessage());
        }
        _timer.start(method(:tick), 250, true);
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
        _assembler = new Dji.Assembler();
        _scanning = true;
        state = "Scanning for DJI camera";
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    function toggleRecord() {
        if (!connected) {
            return;
        }
        log(recording ? "Sending STOP" : "Sending START");
        send(Dji.recordControl(nextSeq(), cameraDeviceId, !recording));
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
            var data = r.getManufacturerSpecificData(Dji.COMPANY_ID);
            // Unlike BiciCAM, do not require byte 2 == 0xFA: the Osmo Nano advertises 0x80 there
            if (data != null && advertisesDjiService(r)) {
                onCameraFound(r, data);
                return;
            }
            r = results.next();
        }
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
        var notify = service.getCharacteristic(Dji.notifyUuid());
        _write = service.getCharacteristic(Dji.writeUuid());
        if (notify == null || _write == null) {
            fail("FFF4/FFF5 missing");
            return;
        }
        var cccd = notify.getDescriptor(BluetoothLowEnergy.cccdUuid());
        if (cccd == null) {
            fail("FFF4 has no CCCD");
            return;
        }
        state = "Enabling notifications";
        try {
            cccd.requestWrite([0x01, 0x00]b);
        } catch (e) {
            fail("CCCD write failed: " + e.getErrorMessage());
        }
    }

    function onDescriptorWrite(descriptor, status) {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            handshake();
        } else {
            fail("CCCD write status " + status);
        }
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

    // ---- Protocol flow ----

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

    // Handshake (protocol_data_segment.md, "Connection Process"): 1. remote asks to connect;
    // 2. camera replies; 3. camera sends its own request with the verdict; 4. remote confirms it.
    hidden function handshake() {
        var firstPairing = Application.Storage.getValue("paired") != true;
        verifyCode = 1000 + Math.rand() % 9000;
        state = "Check camera: code " + verifyCode;
        log(firstPairing ? "Pairing request sent" : "Reconnect request sent");
        send(Dji.connectionRequest(nextSeq(), _deviceId, _mac, firstPairing ? 1 : 0, verifyCode));
    }

    hidden function handleFrame(frame) {
        if (frame.isCommand(Dji.SET_CAMERA, Dji.STATUS_PUSH)) {
            var s = Dji.parseStatus(frame.payload);
            if (s != null) {
                recording = s[:recording];
                battery = s[:battery];
                mode = s[:mode];
            }
            return;
        }
        if (frame.isCommand(Dji.SET_GENERAL, Dji.CONNECTION)) {
            if (frame.isResponse()) {
                onConnectionReply(frame);
            } else {
                onCameraRequest(frame);
            }
            return;
        }
        if (frame.isResponse() && frame.isCommand(Dji.SET_CAMERA, Dji.RECORD_CONTROL)) {
            log("REC reply code " + (frame.payload.size() > 0 ? frame.payload[0] : "?"));
            return;
        }
        log("rx " + frame.cmdSet.format("%02X") + "/" + frame.cmdId.format("%02X") + " len " + frame.payload.size());
    }

    // Step 2: carries the camera model id (0xFF55 = Action 6, the Nano's is unknown)
    hidden function onConnectionReply(frame) {
        if (frame.payload.size() < 5) {
            log("Short connect reply");
            return;
        }
        cameraDeviceId = Dji.u32(frame.payload, 0);
        var code = frame.payload[4];
        log("Connect reply: model " + modelHex() + " code " + code);
        if (code != 0) {
            fail("Camera refused request (code " + code + ")");
        }
    }

    // Step 3 and 4
    hidden function onCameraRequest(frame) {
        var allowed = Dji.verifyResult(frame);
        if (allowed == null) {
            log("Camera request without verdict");
            return;
        }
        if (cameraDeviceId == 0l && frame.payload.size() >= 4) {
            cameraDeviceId = Dji.u32(frame.payload, 0);
        }
        if (!allowed) {
            fail("Camera rejected the connection");
            return;
        }
        // The camera repeats its request until confirmed: confirm repeats without flooding
        var now = System.getTimer();
        if (connected && now - _lastAckAt < 300) {
            return;
        }
        _lastAckAt = now;
        send(Dji.connectionResponse(frame.seq, _deviceId));
        if (!connected) {
            connected = true;
            Application.Storage.setValue("paired", true);
            state = "Connected";
            log("Connected, model " + modelHex());
            send(Dji.statusSubscribe(nextSeq()));
        }
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

    // Watchdog for a write whose callback never arrives, plus screen refresh
    function tick() {
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
        _queue = [];
        _busy = false;
    }

    function modelHex() {
        if (cameraDeviceId == 0l) {
            return "?";
        }
        return "0x" + (cameraDeviceId & 0xFFFFl).toNumber().format("%04X");
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
