# Usage: send_mp3.py <port> <filename.mp3> [--baud 230400] [--to48k [--bitrate 56k]]
#
# Sends an MP3 to the ZedBoard over the USB-UART (frame: "MP3!", u32 LE length, MP3 bytes,
# u32 LE FNV-1a of the MP3) and prints the board's reply. The board only plays 48 kHz mono.
#
# --to48k re-encodes the file with ffmpeg to 48 kHz mono first. That is a second lossy pass,
# so use it only for demos with arbitrary songs; make measurement files directly from the
# master instead:  ffmpeg -i master.wav -ar 48000 -ac 1 -b:a 56k test_56k.mp3
#
# Setup:  pip install -r sw/sender/requirements.txt   (pyserial, and imageio-ffmpeg, which
#         brings its own ffmpeg binary so nothing else needs installing)

import argparse
import struct
import subprocess
import sys
import time

import serial


def transcode_to_48k_mono(path, bitrate):
    """Return the bytes of `path` re-encoded as a 48 kHz mono MP3."""
    try:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        ffmpeg = "ffmpeg"  # fall back to an ffmpeg on PATH
    try:
        out = subprocess.run(
            [ffmpeg, "-v", "error", "-i", path,
             "-ar", "48000", "-ac", "1", "-b:a", bitrate, "-f", "mp3", "pipe:1"],
            capture_output=True, check=True)
    except FileNotFoundError:
        print("ffmpeg not found: pip install -r sw/sender/requirements.txt")
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print("ffmpeg failed:", e.stderr.decode(errors="replace").strip())
        sys.exit(1)
    return out.stdout


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Send an MP3 to the ZedBoard over the USB-UART")
    ap.add_argument("port", help="serial port, e.g. /dev/ttyACM0 or COM3")
    ap.add_argument("file", help="MP3 file")
    ap.add_argument("--baud", type=int, default=230400)
    ap.add_argument("--to48k", action="store_true",
                    help="re-encode to 48 kHz mono with ffmpeg first (demo only, not for measurements)")
    ap.add_argument("--bitrate", default="56k", help="bitrate for --to48k (default 56k)")
    args = ap.parse_args()

    if args.to48k:
        data = transcode_to_48k_mono(args.file, args.bitrate)
        print(f"transcoded to 48 kHz mono {args.bitrate}: not suitable for measurements")
    else:
        with open(args.file, "rb") as file:
            data = file.read()

    if len(data) > 2 * 1024 * 1024:
        print("file too big")
        sys.exit(1)

    h = 0x811C9DC5
    for b in data:
        h = h ^ b
        h = h * 0x01000193
        h = h & 0xFFFFFFFF

    header = struct.pack("<4sI", b"MP3!", len(data))
    trailer = struct.pack("<I", h)
    frame = header + data + trailer

    with serial.Serial(
        port=args.port,
        baudrate=args.baud,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        rtscts=False,
        xonxoff=False,
        timeout=1,
    ) as ser:
        ser.reset_input_buffer()

        # Wait for ready before sending
        start_time = time.time()
        got_ready = False
        while time.time() - start_time < 60:
            if b"**Ready**" in ser.readline():
                got_ready = True
                break

        if not got_ready:
            print("Hang: Never got **Ready**")
            sys.exit(1)

        # send
        print(f"sending {len(data)} bytes, fnv 0x{h:08x}")
        ser.write(frame)
        ser.flush()

        # Wait for reply (full songs take minutes to decode on the ARM) [Claude, 12 Nov]
        start_time = time.time()
        got_reply = False
        while time.time() - start_time < 300:
            line = ser.readline()
            if line:
                print(line.decode(errors="replace").rstrip())
            if b"real time" in line or b"[FAIL]" in line:
                got_reply = True
                if b"[FAIL]" in line:
                    print("Something went wrong")
                    sys.exit(1)
                else:
                    break

        if not got_reply:
            print("hang: never got reply")
            sys.exit(1)

    sys.exit(0)
