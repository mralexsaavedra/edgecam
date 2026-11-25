"""Probe an Osmo Nano with read-only DUML queries from the Mac (full-size BLE packets).

Session as captured from a working iOS remote: notifications on FFF3/4/5/7, 00/2B hello, 07/45 connect,
00/2B keep-alive every second, answer 00/81 and echo 00/74. Then sends GET queries and prints replies.
"""
import asyncio
import sys
import time

from bleak import BleakClient, BleakScanner

U = "0000{}-0000-1000-8000-00805f9b34fb".format
WRITE = U("fff5")
NOTIFY = [U("fff3"), U("fff4"), U("fff5"), U("fff7")]
REMOTE_ID = b"0123456789abcdef0123456789abcdef"  # accepted earlier from nRF Connect
CODE = sys.argv[1].encode() if len(sys.argv) > 1 else b"MACP"


def table(poly):
    t = []
    for i in range(256):
        c = i
        for _ in range(8):
            c = (c >> 1) ^ poly if c & 1 else c >> 1
        t.append(c)
    return t


T8, T16 = table(0x8C), table(0x8408)


def crc8(b):
    c = 0x77
    for x in b:
        c = T8[(c ^ x) & 0xFF]
    return c


def crc16(b):
    c = 0x3692
    for x in b:
        c = (c >> 8) ^ T16[(c ^ x) & 0xFF]
    return c


def encode(src, dst, seq, ctype, cset, cid, payload=b""):
    n = 11 + len(payload) + 2
    o = bytearray(n)
    o[0], o[1], o[2] = 0x55, n & 0xFF, 0x04 | ((n >> 8) & 3)
    o[3] = crc8(o[:3])
    o[4], o[5], o[6], o[7], o[8], o[9], o[10] = src, dst, seq & 0xFF, seq >> 8, ctype, cset, cid
    o[11:11 + len(payload)] = payload
    c = crc16(o[:-2])
    o[-2], o[-1] = c & 0xFF, c >> 8
    return bytes(o)


def parse(buf):
    frames = []
    i = 0
    while i + 13 <= len(buf):
        if buf[i] != 0x55:
            i += 1
            continue
        n = buf[i + 1] | ((buf[i + 2] & 3) << 8)
        f = buf[i:i + n]
        if n < 13 or crc8(f[:3]) != f[3] or len(f) < n or crc16(f[:-2]) != (f[-2] | f[-1] << 8):
            i += 1
            continue
        frames.append(dict(src=f[4], dst=f[5], seq=f[6] | f[7] << 8, type=f[8], set=f[9], id=f[10],
                           payload=bytes(f[11:n - 2]), size=n))
        i += n
    return frames


PROBES = [
    ("camera power info get", 0x01, 0x02, 0x76, b""),
    ("sdcard info get", 0x01, 0x02, 0x71, b""),
    ("camera gps get", 0x01, 0x02, 0x59, b""),
    ("work mode get", 0x01, 0x02, 0x11, b""),
    ("system state get", 0x01, 0x02, 0x70, b""),
    ("battery static get", 0x05, 0x0D, 0x01, b"\x00"),
    ("battery dynamic get", 0x05, 0x0D, 0x02, b"\x00"),
    ("battery cell voltage get", 0x05, 0x0D, 0x03, b"\x00"),
    ("battery common info", 0x05, 0x0D, 0x06, b""),
]

SKIP = {(0x02, 0x80), (0x00, 0x99), (0x0D, 0x02), (0x00, 0xF1)}


async def main():
    print("scanning...")
    dev = await BleakScanner.find_device_by_filter(lambda d, a: (d.name or "").startswith("Osmo"), timeout=20)
    if not dev:
        print("no Osmo camera found")
        return
    print("found", dev.name)
    seq = [0x3000]
    replies = {}
    t0 = time.time()

    def nxt():
        seq[0] = (seq[0] + 1) & 0xFFFF
        return seq[0]

    async with BleakClient(dev) as client:
        print("connected, mtu", client.mtu_size)
        queue = asyncio.Queue()

        def on_notify(_, data):
            queue.put_nowait(bytes(data))

        for u in NOTIFY:
            try:
                await client.start_notify(u, on_notify)
            except Exception as e:
                print("notify", u[4:8], e)

        async def send(frame):
            await client.write_gatt_char(WRITE, frame, response=False)

        async def reader():
            while True:
                data = await queue.get()
                for f in parse(data):
                    key = (f["set"], f["id"])
                    if f["type"] & 0x80:
                        replies[f["seq"]] = f
                        print("  %6.2f reply %02X/%02X from %02X (%d bytes): %s" % (
                            time.time() - t0, f["set"], f["id"], f["src"], f["size"], f["payload"].hex()))
                    elif key == (0x00, 0x81):
                        await send(encode(0x02, f["src"], f["seq"], 0xC0, 0x00, 0x81,
                                          bytes.fromhex("0041505000" + "00" * 36 + "02" + "00" * 8 + "0208" + "00" * 10)))
                    elif key == (0x00, 0x74):
                        await send(encode(0x02, f["src"], f["seq"], 0xC0, 0x00, 0x74, f["payload"]))
                    elif key not in SKIP:
                        print("  %6.2f push %02X/%02X from %02X: %s" % (time.time() - t0, f["set"], f["id"], f["src"], f["payload"].hex()))

        async def keepalive():
            while True:
                await asyncio.sleep(1)
                await send(encode(0x02, 0xF0, nxt(), 0x40, 0x00, 0x2B, b"\x01\x01"))

        tasks = [asyncio.create_task(reader()), asyncio.create_task(keepalive())]
        await send(encode(0x02, 0xF0, nxt(), 0x40, 0x00, 0x2B, b"\x04\x00"))
        s = nxt()
        await send(encode(0x02, 0x07, s, 0x40, 0x07, 0x45, b"\x20" + REMOTE_ID + bytes([len(CODE)]) + CODE))
        print("connect sent, code", CODE.decode(), "- accept on the camera if it asks")
        for _ in range(60):
            if s in replies:
                break
            await asyncio.sleep(0.5)
        await asyncio.sleep(3)
        for name, dst, cset, cid, payload in PROBES:
            s = nxt()
            print("probe:", name, "%02X/%02X -> %02X" % (cset, cid, dst))
            await send(encode(0x02, dst, s, 0x40, cset, cid, payload))
            for _ in range(8):
                if s in replies:
                    break
                await asyncio.sleep(0.25)
            if s not in replies:
                print("  no reply")
        await asyncio.sleep(2)
        for t in tasks:
            t.cancel()


asyncio.run(main())
