# Usage: send_mp3.py <port> <filename.mp3> [--baud 230400]


import struct
import sys
import time

import serial

if __name__ == "__main__":
    h = 0x811C9DC5
    header = None
    trailer = None
    frame = None

    with open(sys.argv[2], "rb") as file:
        data = file.read()

        if len(data) > 2 * 1024 * 1024:
            print("file too big")
            sys.exit(1)

        for b in data:
            h = h ^ b
            h = h * 0x01000193
            h = h & 0xFFFFFFFF

        header = struct.pack("<4sI", b"MP3!", len(data))
        trailer = struct.pack("<I", h)
        frame = header + data + trailer

    with serial.Serial(
        port=sys.argv[1],
        baudrate=int(sys.argv[4])
        if len(sys.argv) > 4 and sys.argv[3] == "--baud"
        else 230400,
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
            if b"**Ready**" not in ser.readline():
                pass
            else:
                got_ready = True
                break

        if not got_ready:
            print("Hang: Never got **Ready**")
            sys.exit(1)

        # send
        print(f"sending {len(data)} bytes, fnv 0x{h:08x}")
        _ = ser.write(frame)
        ser.flush()

        # Wait for reply
        start_time = time.time()
        got_reply = False
        while time.time() - start_time < 60:
            line = ser.readline()
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
