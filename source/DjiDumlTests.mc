// DUML frames taken verbatim from a Bluetooth capture of an iOS remote driving an Osmo Nano.

import Toybox.Lang;
import Toybox.Test;

(:test)
function dumlHelloMatchesCapture(logger) {
    return Duml.toHex(Duml.hello(0x20CF)).equals("550F04A202F0CF2040002B0400088D");
}

(:test)
function dumlRecordStartMatchesCapture(logger) {
    var got = Duml.toHex(Duml.record(0xF9CF, true));
    logger.debug(got);
    return got.equals("550E04660201CFF94002020130B0");
}

(:test)
function dumlRecordStopMatchesCapture(logger) {
    return Duml.toHex(Duml.record(0x01D0, false)).equals("550E04660201D00140020200061B");
}

(:test)
function dumlAnswer81MatchesCapture(logger) {
    var request = new Duml.Frame(0x48, 0x02, 0x0A25, Duml.REQUEST, 0x00, 0x81, []b);
    var got = Duml.toHex(Duml.answer81(request));
    logger.debug(got);
    return got.equals("554B04020248250AC000810041505000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000020800000000000000000000C152");
}

(:test)
function dumlEchoMatchesCapture(logger) {
    var request = new Duml.Frame(0x88, 0x02, 0x04B2, Duml.REQUEST, 0x00, 0x74, [0x29, 0x01]b);
    return Duml.toHex(Duml.echo(request)).equals("550F04A20288B204C000742901B143");
}

(:test)
function dumlConnectHasCapturedLayout(logger) {
    var frame = Duml.connect(0xCF21, "0123456789abcdef0123456789abcdef", "MCAM");
    // Same length as the captured 07/45 frame (0x33), addressed 02 -> 07
    return frame.size() == 0x33 && frame[4] == 0x02 && frame[5] == 0x07 && frame[9] == 0x07 && frame[10] == 0x45
        && frame[11] == 0x20 && frame[44] == 4;
}

(:test)
function dumlAssemblerReadsSplitStatusAndSkipsNoise(logger) {
    var status = Duml.fromHex("5549049301027633000280010280000101C0000000C00000000000009C0D00000000000000000000000000007000000100000000000000000000000000000000000000000100007CDE");
    var a = new Duml.Assembler();
    if (a.feed(Duml.fromHex("AA0102")).size() != 0) { return false; }
    if (a.feed(status.slice(0, 20)).size() != 0) { return false; }
    if (a.feed(status.slice(20, 40)).size() != 0) { return false; }
    var frames = a.feed(status.slice(40, null));
    return frames.size() == 1 && frames[0].src == 0x01 && frames[0].isCommand(0x02, 0x80)
        && !Duml.isRecording(frames[0].payload);
}

(:test)
function dumlRecordingBit(logger) {
    return Duml.isRecording([0x81, 0x02]b) && Duml.isRecording([0xC1]b) && !Duml.isRecording([0x01]b)
        && !Duml.isRecording([0x41]b);
}

// On the Edge each notification is cut to 20 bytes: a status push still says whether it records
(:test)
function dumlReadsTruncatedStatus(logger) {
    var idle = Duml.fromHex("5549049301027633000280010280000101C00000");
    var rec = Duml.fromHex("5549049301027633000280810280000101C00000");
    var a = Duml.parseNotification(idle);
    var b = Duml.parseNotification(rec);
    return a.size() == 1 && a[0].isCommand(0x02, 0x80) && !Duml.isRecording(a[0].payload)
        && b.size() == 1 && Duml.isRecording(b[0].payload);
}

(:test)
function dumlReadsWholeReplyAndRejectsBadHeader(logger) {
    var reply = Duml.parseNotification(Duml.fromHex("550F04A207020210C0074500023093"));
    var junk = Duml.parseNotification(Duml.fromHex("5549049401027633000280010280000101C00000"));
    return reply.size() == 1 && reply[0].isResponse() && reply[0].isCommand(0x07, 0x45)
        && reply[0].payload.size() == 2 && reply[0].payload[1] == 0x02 && junk.size() == 0;
}
