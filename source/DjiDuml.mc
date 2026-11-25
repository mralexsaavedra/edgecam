// DJI DUML, the internal protocol the Osmo Nano speaks over FFF4/FFF5.
// Reverse-engineered from a Bluetooth capture of a third-party iOS remote talking to an Osmo Nano;
// DJI does not document it.
//
// Frame (little-endian):
// [0x55][Len:10 bits | Ver:6 bits][CRC8][Src][Dst][Seq:2][CmdType][CmdSet][CmdId][payload][CRC16:2]
// CRC8 covers bytes 0..2 (seed 0x77), CRC16 covers everything before it (seed 0x3692),
// both reflected (polys 0x8C and 0x8408). Version is 1 (byte 2 = 0x04 | len high bits).

import Toybox.BluetoothLowEnergy;
import Toybox.Lang;

module Duml {
    // DJI's Bluetooth company id (manufacturer data); the Edge does not expose it for the Nano
    const COMPANY_ID = 0x08AA;
    const SOF = 0x55;
    const HEADER = 11;
    const MIN_SIZE = 13;

    // Device addresses seen in the capture
    const APP = 0x02;
    const CAMERA = 0x01;
    const BROADCAST = 0xF0;

    const REQUEST = 0x40;
    const RESPONSE = 0xC0;

    var _crc8Table = null;
    var _crc16Table = null;

    function crc8Table() {
        if (_crc8Table == null) {
            _crc8Table = new [256];
            for (var i = 0; i < 256; i++) {
                var c = i;
                for (var k = 0; k < 8; k++) {
                    c = ((c & 1) != 0) ? ((c >> 1) ^ 0x8C) : (c >> 1);
                }
                _crc8Table[i] = c;
            }
        }
        return _crc8Table;
    }

    function crc16Table() {
        if (_crc16Table == null) {
            _crc16Table = new [256];
            for (var i = 0; i < 256; i++) {
                var c = i;
                for (var k = 0; k < 8; k++) {
                    c = ((c & 1) != 0) ? ((c >> 1) ^ 0x8408) : (c >> 1);
                }
                _crc16Table[i] = c;
            }
        }
        return _crc16Table;
    }

    function crc8(data, length) {
        var t = crc8Table();
        var c = 0x77;
        for (var i = 0; i < length; i++) {
            c = t[(c ^ data[i]) & 0xFF];
        }
        return c;
    }

    function crc16(data, length) {
        var t = crc16Table();
        var c = 0x3692;
        for (var i = 0; i < length; i++) {
            c = ((c >> 8) ^ t[(c ^ data[i]) & 0xFF]) & 0xFFFF;
        }
        return c;
    }

    class Frame {
        var src;
        var dst;
        var seq;
        var cmdType;
        var cmdSet;
        var cmdId;
        var payload;

        function initialize(aSrc, aDst, aSeq, aCmdType, aCmdSet, aCmdId, aPayload) {
            src = aSrc;
            dst = aDst;
            seq = aSeq;
            cmdType = aCmdType;
            cmdSet = aCmdSet;
            cmdId = aCmdId;
            payload = aPayload;
        }

        function isResponse() {
            return (cmdType & 0x80) != 0;
        }

        function isCommand(set, id) {
            return cmdSet == set && cmdId == id;
        }

        function key() {
            return cmdSet.format("%02X") + "/" + cmdId.format("%02X");
        }
    }

    function encode(src, dst, seq, cmdType, cmdSet, cmdId, payload) {
        var total = HEADER + payload.size() + 2;
        var out = new [total]b;
        out[0] = SOF;
        out[1] = total & 0xFF;
        out[2] = 0x04 | ((total >> 8) & 0x03);
        out[3] = crc8(out, 3);
        out[4] = src;
        out[5] = dst;
        out[6] = seq & 0xFF;
        out[7] = (seq >> 8) & 0xFF;
        out[8] = cmdType;
        out[9] = cmdSet;
        out[10] = cmdId;
        for (var i = 0; i < payload.size(); i++) {
            out[HEADER + i] = payload[i];
        }
        var c = crc16(out, total - 2);
        out[total - 2] = c & 0xFF;
        out[total - 1] = (c >> 8) & 0xFF;
        return out;
    }

    // Rebuilds DUML frames from notifications; skips anything else (R SDK frames start with 0xAA)
    class Assembler {
        var _buf;

        function initialize() {
            _buf = []b;
        }

        function feed(chunk) {
            _buf = _buf.addAll(chunk);
            var frames = [];
            while (true) {
                var start = -1;
                for (var i = 0; i < _buf.size(); i++) {
                    if (_buf[i] == SOF) {
                        start = i;
                        break;
                    }
                }
                if (start < 0) {
                    _buf = []b;
                    break;
                }
                if (start > 0) {
                    _buf = _buf.slice(start, null);
                }
                if (_buf.size() < 4) {
                    break;
                }
                var length = _buf[1] | ((_buf[2] & 0x03) << 8);
                if (length < MIN_SIZE || crc8(_buf, 3) != _buf[3]) {
                    _buf = _buf.slice(1, null);
                    continue;
                }
                if (_buf.size() < length) {
                    break;
                }
                if (crc16(_buf, length - 2) == (_buf[length - 2] | (_buf[length - 1] << 8))) {
                    frames.add(new Frame(_buf[4], _buf[5], _buf[6] | (_buf[7] << 8), _buf[8], _buf[9], _buf[10],
                        _buf.slice(HEADER, length - 2)));
                    _buf = _buf.slice(length, null);
                } else {
                    _buf = _buf.slice(1, null);
                }
            }
            return frames;
        }
    }

    // Parses one BLE notification. Connect IQ only delivers the first 20 bytes of each notification
    // (default MTU), so longer camera frames arrive cut short: when the header checks out (CRC8) the
    // frame is still returned with whatever payload arrived, and CRC16 is only checked on whole frames.
    function parseNotification(value) {
        var frames = [];
        var at = 0;
        while (at + HEADER <= value.size()) {
            if (value[at] != SOF) {
                at++;
                continue;
            }
            var frame = value.slice(at, null);
            var length = frame[1] | ((frame[2] & 0x03) << 8);
            if (length < MIN_SIZE || crc8(frame, 3) != frame[3]) {
                at++;
                continue;
            }
            var whole = frame.size() >= length;
            if (whole && crc16(frame, length - 2) != (frame[length - 2] | (frame[length - 1] << 8))) {
                at++;
                continue;
            }
            var end = whole ? length - 2 : frame.size();
            frames.add(new Frame(frame[4], frame[5], frame[6] | (frame[7] << 8), frame[8], frame[9], frame[10],
                frame.slice(HEADER, end)));
            if (!whole) {
                break;
            }
            at += length;
        }
        return frames;
    }

    // ---- Helpers ----

    function uuid(short) {
        return BluetoothLowEnergy.stringToUuid("0000" + short + "-0000-1000-8000-00805f9b34fb");
    }

    function serviceUuid() {
        return uuid("fff0");
    }

    // Remote -> camera (write without response)
    function writeUuid() {
        return uuid("fff5");
    }

    // The characteristics whose notifications the iOS remote enabled, in its order
    function notifyUuids() {
        return [uuid("fff3"), uuid("fff4"), uuid("fff5"), uuid("fff7")];
    }

    function toHex(data) {
        var s = "";
        for (var i = 0; i < data.size(); i++) {
            s += data[i].format("%02X");
        }
        return s;
    }

    function fromHex(text) {
        var out = new [text.length() / 2]b;
        for (var i = 0; i < out.size(); i++) {
            out[i] = text.substring(2 * i, 2 * i + 2).toNumberWithBase(16);
        }
        return out;
    }

    // ---- Commands seen in the capture ----

    // 00/2B to broadcast: 04 00 once at start, then 01 01 every second as keep-alive
    function hello(seq) {
        return encode(APP, BROADCAST, seq, REQUEST, 0x00, 0x2B, [0x04, 0x00]b);
    }

    function keepAlive(seq) {
        return encode(APP, BROADCAST, seq, REQUEST, 0x00, 0x2B, [0x01, 0x01]b);
    }

    // 07/45 to 0x07: introduces the remote. Payload: 0x20, a 32-char id, name length, name.
    // The camera answered 00 01 to the iOS remote it already knew.
    function connect(seq, id32, name) {
        var payload = [0x20]b;
        payload.addAll(id32.toUtf8Array());
        payload.add(name.length());
        payload.addAll(name.toUtf8Array());
        return encode(APP, 0x07, seq, REQUEST, 0x07, 0x45, payload);
    }

    // 02/02 to the camera: 01 starts recording, 00 stops. The camera answers 00 when accepted.
    function record(seq, start) {
        return encode(APP, CAMERA, seq, REQUEST, 0x02, 0x02, [start ? 0x01 : 0x00]b);
    }

    // Answers the iOS remote always gave to the camera's periodic 00/81 request
    function answer81(request) {
        var payload = new [62]b;
        payload[1] = 0x41; // "APP"
        payload[2] = 0x50;
        payload[3] = 0x50;
        payload[41] = 0x02;
        payload[50] = 0x02;
        payload[51] = 0x08;
        return encode(APP, request.src, request.seq, RESPONSE, request.cmdSet, request.cmdId, payload);
    }

    // The camera's 00/74 request is echoed back
    function echo(request) {
        return encode(APP, request.src, request.seq, RESPONSE, request.cmdSet, request.cmdId, request.payload);
    }

    // 02/80 camera status pushed twice a second: bit 7 of byte 0 is set while recording
    function isRecording(status) {
        return status.size() > 0 && (status[0] & 0x80) != 0;
    }
}
