#!/usr/bin/env python3
# NOT TEAM CODE - test scaffolding written by Claude.
#
# Pretends to be the ZedBoard running sw/app (BOARD build) on a serial port, so
# send_mp3.py can be tested without hardware. It follows main_host.c: prints
# **Ready**, reads the 8-byte header, checks magic and length, reads the payload and
# trailer, checks FNV-1a, and prints the same lines the board prints. With --decoder it
# runs the PC build of sw/app on the received bytes to produce real res.* lines.
#
# Make a linked pair of virtual serial ports first:
#   socat -d -d pty,raw,echo=0 pty,raw,echo=0      (prints two /dev/pts/N paths)
# then:
#   python3 fake_board.py /dev/pts/A [--decoder path/to/pc_build]
#   python3 send_mp3.py   /dev/pts/B file.mp3

import argparse
import os
import struct
import subprocess
import sys
import tempfile
import time

import serial

MAX_MP3_LEN = 2 * 1024 * 1024
RX_TIMEOUT_S = 30


def fnv1a(data):
    h = 0x811C9DC5
    for b in data:
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return h


def read_exact(ser, n, timeout_s):
    """Read n bytes or give up after timeout_s; returns what arrived."""
    buf = bytearray()
    deadline = time.monotonic() + timeout_s
    while len(buf) < n and time.monotonic() < deadline:
        buf += ser.read(n - len(buf))
    return bytes(buf)


def say(ser, text):
    ser.write((text + "\r\n").encode())
    ser.flush()
    print("board>", text)


def main():
    ap = argparse.ArgumentParser(description="Fake ZedBoard for testing send_mp3.py")
    ap.add_argument("port")
    ap.add_argument("--baud", type=int, default=230400)
    ap.add_argument("--decoder", help="PC build of sw/app (main_host.c + decode.c)")
    args = ap.parse_args()

    with serial.Serial(args.port, args.baud, timeout=0.5) as ser:
        ser.reset_input_buffer()
        say(ser, "**Ready**")

        hdr = read_exact(ser, 8, RX_TIMEOUT_S)
        if len(hdr) < 8:
            say(ser, "[FAIL] header timeout, got %d of 8 bytes" % len(hdr))
            return 7
        if hdr[:4] != b"MP3!":
            say(ser, "[FAIL] bad magic %02x %02x %02x %02x" % tuple(hdr[:4]))
            return 6
        (length,) = struct.unpack("<I", hdr[4:])
        if length == 0 or length > MAX_MP3_LEN:
            say(ser, "[FAIL] length %d out of range (max %d)" % (length, MAX_MP3_LEN))
            return 6

        body = read_exact(ser, length + 4, RX_TIMEOUT_S)
        if len(body) < length + 4:
            say(ser, "[FAIL] payload timeout, got %d of %d bytes" % (len(body), length + 4))
            return 7

        payload = body[:length]
        (expected,) = struct.unpack("<I", body[length:])
        actual = fnv1a(payload)
        say(ser, "rx: %d bytes, 0 uart errors, fnv 0x%08x (sender 0x%08x)" % (length, actual, expected))
        if actual != expected:
            say(ser, "[FAIL] checksum mismatch")
            return 8

        if args.decoder:
            with tempfile.TemporaryDirectory() as d:
                mp3 = os.path.join(d, "rx.mp3")
                with open(mp3, "wb") as f:
                    f.write(payload)
                out = subprocess.run([args.decoder, mp3, os.path.join(d, "rx.raw")],
                                     capture_output=True, text=True)
            res = {}
            for line in out.stdout.splitlines():
                if line.startswith("res."):
                    say(ser, line)
                    key, _, val = line.partition(" = ")
                    res[key] = val
            if out.returncode != 0:
                say(ser, "[FAIL] decode() returned SIG_DECODE_FAIL")
                return 4
            # same rule as main_host.c: the PL plays 48 kHz mono only
            rate, ch = res.get("res.sample_rate"), res.get("res.channel_count")
            if rate != "48000" or ch != "1":
                say(ser, "[FAIL] need 48 kHz mono, got %s Hz %s ch (send with --to48k)" % (rate, ch))
                return 9
        else:
            say(ser, "res.checksum = 0x00000000 (no --decoder given)")
        say(ser, "decode 0 ms for 0 ms of audio (x0 real time)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
