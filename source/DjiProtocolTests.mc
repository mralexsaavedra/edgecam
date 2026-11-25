// Reference frames published by DJI in Osmo-GPS-Controller-Demo, the same ones BiciCAM tests against.
// Run with: monkeyc ... --unit-test, then monkeydo bin/edgecam.prg edge540 -t

import Toybox.Lang;
import Toybox.Test;

// docs/protocol_data_segment.md, mode switch to Hyperlapse
const MODE_SWITCH_HEX = "AA1B0001000000000500 57EE1D0400 0033FF0A01473936F4FAE1D0";
// test/connect_cmd_frame_builder/connect_cmd_frame.txt, first line
const CONNECTION_HEX = "AA330002000000000100982F00197856341206383456789ABC00000000000000000000000000000000FE1F00000000796C667C";

(:test)
function encodesModeSwitchLikeDji(logger) {
    var frame = Dji.encode(0x1D, 0x04, 5, Dji.RESPONSE_OPTIONAL, Dji.fromHex("000033FF0A01473936"));
    var got = Dji.toHex(frame);
    logger.debug(got);
    return got.equals(Dji.toHex(Dji.fromHex(MODE_SWITCH_HEX)));
}

(:test)
function connectionRequestMatchesDjiDemo(logger) {
    var frame = Dji.connectionRequest(1, 0x12345678l, Dji.fromHex("383456789ABC"), 0, 0x1FFE);
    var got = Dji.toHex(frame);
    logger.debug(got);
    return got.equals(CONNECTION_HEX);
}

(:test)
function assemblerRebuildsSplitFramesAndSkipsNoise(logger) {
    var modeSwitch = Dji.fromHex(MODE_SWITCH_HEX);
    var connection = Dji.fromHex(CONNECTION_HEX);
    var a = new Dji.Assembler();
    // DUML telemetry (0x55...) with a stray 0xAA, then the frame split in three notifications
    if (a.feed(Dji.fromHex("550D04AA330201")).size() != 0) { return false; }
    if (a.feed(modeSwitch.slice(0, 7)).size() != 0) { return false; }
    if (a.feed(modeSwitch.slice(7, 20)).size() != 0) { return false; }
    var frames = a.feed(modeSwitch.slice(20, null).addAll(connection));
    return frames.size() == 2
        && frames[0].isCommand(0x1D, 0x04) && frames[0].seq == 5 && !frames[0].isResponse()
        && frames[1].isCommand(0x00, 0x19) && frames[1].payload.size() == 33;
}

(:test)
function assemblerDropsBrokenCrc32(logger) {
    var broken = Dji.fromHex(MODE_SWITCH_HEX);
    broken[16] = 0x00;
    return new Dji.Assembler().feed(broken).size() == 0;
}

(:test)
function readsCameraVerdict(logger) {
    var accepted = new Dji.Frame(0x00, 0x19, 9, Dji.RESPONSE_REQUIRED, Dji.fromHex("55FF0000" + "00000000000000000000000000000000000000000000" + "02000000000000"));
    var rejected = new Dji.Frame(0x00, 0x19, 9, Dji.RESPONSE_REQUIRED, Dji.fromHex("55FF0000" + "00000000000000000000000000000000000000000000" + "02010000000000"));
    var noVerdict = new Dji.Frame(0x00, 0x19, 9, Dji.RESPONSE_REQUIRED, Dji.fromHex("55FF0000" + "00000000000000000000000000000000000000000000" + "01000000000000"));
    return Dji.verifyResult(accepted) == true
        && Dji.verifyResult(rejected) == false
        && Dji.verifyResult(noVerdict) == null;
}

(:test)
function recordAndSubscribePayloads(logger) {
    var start = Dji.recordControl(2, 0xFF55l, true);
    var stop = Dji.recordControl(3, 0xFF55l, false);
    var sub = Dji.statusSubscribe(5);
    return Dji.toHex(payloadOf(start)).equals("55FF00000000000000")
        && Dji.toHex(payloadOf(stop)).equals("55FF00000100000000")
        && Dji.toHex(payloadOf(sub)).equals("031400000000");
}

// The payload sits between the 14-byte header and the 4-byte CRC32
function payloadOf(frame) {
    return frame.slice(14, frame.size() - 4);
}

(:test)
function parsesStatus(logger) {
    var data = new [38]b;
    data[0] = 0x01;
    data[1] = 0x03;
    data[5] = 0x2C;
    data[6] = 0x01;
    data[37] = 87;
    var s = Dji.parseStatus(data);
    return s[:recording] && s[:recordSeconds] == 300 && s[:battery] == 87
        && Dji.parseStatus(new [20]b) == null;
}
