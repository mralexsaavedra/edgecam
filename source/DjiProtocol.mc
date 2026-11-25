// DJI R SDK remote protocol, as used by the Osmo Action GPS Bluetooth remote.
// Ported from BiciCAM (MIT, BiciLAB Factory SL / Horst Tellioglu), which follows DJI's
// Osmo-GPS-Controller-Demo (docs/protocol.md, docs/protocol_data_segment.md).
//
// Frame (little-endian):
// [0xAA][Ver/Len:2][CmdType:1][Enc:1][Res:3][Seq:2][CRC16:2][CmdSet:1][CmdId:1][data][CRC32:4]
// CRC16 covers bytes 0..9, CRC32 covers everything before it. Both start at 0x3AA3, no final XOR.

import Toybox.BluetoothLowEnergy;
import Toybox.Lang;

module Dji {
    const COMPANY_ID = 0x08AA;

    const SOF = 0xAA;
    const HEADER = 12;
    const MIN_SIZE = 18;

    const NO_RESPONSE = 0x00;
    const RESPONSE_OPTIONAL = 0x01;
    const RESPONSE_REQUIRED = 0x02;
    const RESPONSE = 0x20;

    const SET_GENERAL = 0x00;
    const SET_CAMERA = 0x1D;
    const CONNECTION = 0x19;
    const STATUS_PUSH = 0x02;
    const RECORD_CONTROL = 0x03;
    const STATUS_SUBSCRIBE = 0x05;

    // Position of verify_mode in the connection request payload; verify_data follows it
    const VERIFY_MODE_AT = 26;

    var _crc16Table = null;
    var _crc32Table = null;

    function serviceUuid() {
        return BluetoothLowEnergy.stringToUuid("0000fff0-0000-1000-8000-00805f9b34fb");
    }

    // Camera -> remote (notify)
    function notifyUuid() {
        return BluetoothLowEnergy.stringToUuid("0000fff4-0000-1000-8000-00805f9b34fb");
    }

    // Remote -> camera (write without response)
    function writeUuid() {
        return BluetoothLowEnergy.stringToUuid("0000fff5-0000-1000-8000-00805f9b34fb");
    }

    // ---- CRC ----

    function crc16Table() {
        if (_crc16Table == null) {
            _crc16Table = new [256];
            for (var i = 0; i < 256; i++) {
                var c = i;
                for (var k = 0; k < 8; k++) {
                    c = ((c & 1) != 0) ? ((c >> 1) ^ 0xA001) : (c >> 1);
                }
                _crc16Table[i] = c;
            }
        }
        return _crc16Table;
    }

    function crc32Table() {
        if (_crc32Table == null) {
            _crc32Table = new [256];
            for (var i = 0; i < 256; i++) {
                var c = i.toLong();
                for (var k = 0; k < 8; k++) {
                    c = ((c & 1l) != 0l) ? ((c >> 1) ^ 0xEDB88320l) : (c >> 1);
                }
                _crc32Table[i] = c;
            }
        }
        return _crc32Table;
    }

    function crc16(data, length) {
        var t = crc16Table();
        var crc = 0x3AA3;
        for (var i = 0; i < length; i++) {
            crc = (t[(crc ^ data[i]) & 0xFF] ^ (crc >> 8)) & 0xFFFF;
        }
        return crc;
    }

    function crc32(data, length) {
        var t = crc32Table();
        var crc = 0x3AA3l;
        for (var i = 0; i < length; i++) {
            crc = (t[((crc ^ data[i]) & 0xFFl).toNumber()] ^ (crc >> 8)) & 0xFFFFFFFFl;
        }
        return crc;
    }

    // ---- Byte helpers ----

    function u16(data, at) {
        return data[at] | (data[at + 1] << 8);
    }

    function u32(data, at) {
        return data[at].toLong() | (data[at + 1].toLong() << 8) | (data[at + 2].toLong() << 16) | (data[at + 3].toLong() << 24);
    }

    function putU16(data, at, value) {
        data[at] = value & 0xFF;
        data[at + 1] = (value >> 8) & 0xFF;
    }

    function putU32(data, at, value) {
        var v = value.toLong();
        for (var i = 0; i < 4; i++) {
            data[at + i] = ((v >> (8 * i)) & 0xFFl).toNumber();
        }
    }

    function toHex(data) {
        var s = "";
        for (var i = 0; i < data.size(); i++) {
            s += data[i].format("%02X");
        }
        return s;
    }

    function fromHex(text) {
        var clean = "";
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] != ' ') {
                clean += chars[i].toString();
            }
        }
        var out = new [clean.length() / 2]b;
        for (var i = 0; i < out.size(); i++) {
            out[i] = clean.substring(2 * i, 2 * i + 2).toNumberWithBase(16);
        }
        return out;
    }

    // ---- Frames ----

    class Frame {
        var cmdSet;
        var cmdId;
        var seq;
        var cmdType;
        var payload;

        function initialize(aCmdSet, aCmdId, aSeq, aCmdType, aPayload) {
            cmdSet = aCmdSet;
            cmdId = aCmdId;
            seq = aSeq;
            cmdType = aCmdType;
            payload = aPayload;
        }

        function isResponse() {
            return (cmdType & RESPONSE) != 0;
        }

        function isCommand(set, id) {
            return cmdSet == set && cmdId == id;
        }
    }

    function encode(cmdSet, cmdId, seq, cmdType, payload) {
        var total = HEADER + 2 + payload.size() + 4;
        var out = new [total]b;
        out[0] = SOF;
        out[1] = total & 0xFF;
        out[2] = (total >> 8) & 0x03; // version (bits 15..10) is 0
        out[3] = cmdType;
        // out[4] encryption (0: none), out[5..7] reserved
        out[8] = seq & 0xFF;
        out[9] = (seq >> 8) & 0xFF;
        putU16(out, 10, crc16(out, 10));
        out[12] = cmdSet;
        out[13] = cmdId;
        for (var i = 0; i < payload.size(); i++) {
            out[14 + i] = payload[i];
        }
        putU32(out, total - 4, crc32(out, total - 4));
        return out;
    }

    // Rebuilds R SDK frames from notifications, which may carry half a frame, several frames,
    // or frames of another protocol (DUML, starting with 0x55).
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
                if (_buf.size() < HEADER) {
                    break;
                }
                var length = u16(_buf, 1) & 0x3FF;
                if (length < MIN_SIZE || crc16(_buf, 10) != u16(_buf, 10)) {
                    // A stray 0xAA inside other data
                    _buf = _buf.slice(1, null);
                    continue;
                }
                if (_buf.size() < length) {
                    break;
                }
                if (crc32(_buf, length - 4) == u32(_buf, length - 4)) {
                    frames.add(new Frame(_buf[12], _buf[13], u16(_buf, 8), _buf[3], _buf.slice(14, length - 4)));
                    _buf = _buf.slice(length, null);
                } else {
                    _buf = _buf.slice(1, null);
                }
            }
            return frames;
        }
    }

    // ---- Commands ----

    // Connection request (00/19). verifyMode 1: first pairing, the camera shows the code and asks;
    // 0: already paired, the camera decides from its history whether to ask again.
    function connectionRequest(seq, deviceId, mac, verifyMode, verifyCode) {
        var data = new [33]b;
        putU32(data, 0, deviceId);
        data[4] = mac.size();
        for (var i = 0; i < mac.size(); i++) {
            data[5 + i] = mac[i];
        }
        // 21..24 fw_version = 0 (no firmware offers), 25 conidx = 0
        data[VERIFY_MODE_AT] = verifyMode;
        putU16(data, VERIFY_MODE_AT + 1, verifyCode);
        return encode(SET_GENERAL, CONNECTION, seq, RESPONSE_REQUIRED, data);
    }

    // Reply to the camera's own connection request, with the camera's sequence number.
    // Without it the camera keeps repeating its request.
    function connectionResponse(cameraSeq, deviceId) {
        var data = new [9]b;
        putU32(data, 0, deviceId);
        // data[4] ret_code 0, data[5..8] camera index 0
        return encode(SET_GENERAL, CONNECTION, cameraSeq, RESPONSE | NO_RESPONSE, data);
    }

    // Verdict inside the camera's connection request (verify_mode 2): true accepted, false rejected,
    // null when the frame carries no verdict.
    function verifyResult(frame) {
        if (!frame.isCommand(SET_GENERAL, CONNECTION) || frame.isResponse()) {
            return null;
        }
        var data = frame.payload;
        if (data.size() < VERIFY_MODE_AT + 3 || data[VERIFY_MODE_AT] != 2) {
            return null;
        }
        return u16(data, VERIFY_MODE_AT + 1) == 0;
    }

    // Start (0) or stop (1) recording (1D/03).
    function recordControl(seq, cameraDeviceId, start) {
        var data = new [9]b;
        putU32(data, 0, cameraDeviceId);
        data[4] = start ? 0 : 1;
        return encode(SET_CAMERA, RECORD_CONTROL, seq, RESPONSE_OPTIONAL, data);
    }

    // Status subscription (1D/05): mode 3 (periodic and on change) at 2 Hz.
    function statusSubscribe(seq) {
        var data = [3, 20, 0, 0, 0, 0]b;
        return encode(SET_CAMERA, STATUS_SUBSCRIBE, seq, NO_RESPONSE, data);
    }

    // Status pushed by the camera (1D/02). Returns null if too short.
    function parseStatus(data) {
        if (data.size() < 38) {
            return null;
        }
        return {
            :mode => data[0],
            :cameraStatus => data[1],
            :recording => data[1] == 3,
            :recordSeconds => u16(data, 5),
            :battery => data[37]
        };
    }
}
