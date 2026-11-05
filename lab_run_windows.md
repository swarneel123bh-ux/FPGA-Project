# Lab run on Windows: send an MP3 to the ZedBoard and decode it

*Written by Claude as a lab guide (not graded team code). For the lab's Windows PCs with
Vivado/Vitis 2020.2. Assumes you have never used the ZedBoard, Vitis or this repository.*

---

## 0. What this test does, in one paragraph

A song file (MP3) is sent from the PC to the ZedBoard over a USB cable. A small C program running
on the board's ARM processor receives the file, checks that not a single byte was lost, turns the
MP3 into raw audio samples ("decoding"), and prints a short report back to the PC. **No sound
comes out yet**; that needs the codec code another team member is writing. Success means the
report shows zero lost bytes and the same numbers the PC got for the same file.

### Words used below

| Word | Meaning here |
|---|---|
| **ZedBoard** | The green development board. Its main chip, the **Zynq**, holds an ARM processor (the **PS**, processing system) and an FPGA (the **PL**, programmable logic). This test uses only the ARM. |
| **Vitis** | Xilinx's program for writing C code for the ARM, compiling it, and loading it into the board. |
| **Vivado** | Xilinx's program for designing the FPGA hardware. **Not needed for this test.** |
| **JTAG** | A debug connection. Vitis uses it to load your program into the board. |
| **UART** | A simple serial connection (bytes, one after the other). Our song travels over it. |
| **COM port** | The name Windows gives a serial connection, e.g. `COM5`. |
| **Baud rate** | Speed of the serial connection. Ours is 230,400 bits/s, about 23 KB/s. |
| **XSA file** | A description of the board's hardware that Vitis needs to build a program for it. |
| **Fingerprint (FNV-1a checksum)** | A 32-bit number computed from every byte of some data, written like `0x95b73db9`. If even one byte changes, the number changes. We compare fingerprints instead of comparing whole files. |

---

## 1. How one PC talks to the board: two cables, two jobs

The ZedBoard has **two micro-USB sockets**. Plug **both** into the same PC. They do different
jobs and never share a connection:

```
                  ┌── cable 1 → J17, label "PROG"  (JTAG) ── Vitis loads the program into the ARM
   lab PC ────────┤
                  └── cable 2 → J14, label "UART"  (COMn) ── send_mp3.py sends the song and reads the replies
```

- **J17 / PROG (JTAG)** is used only by Vitis. Windows does **not** show a COM port for it, and you
  never type a port for it: Vitis finds the board by itself.
- **J14 / UART** shows up in Windows as a COM port, e.g. `COM5`. Our Python script `send_mp3.py`
  opens it, sends the song, and prints everything the board says back.
- **Only one program can open a COM port at a time.** While `send_mp3.py` runs, do **not** open
  PuTTY, Tera Term, or the Vitis "Serial Terminal" on the same port.

---

## 2. Before the lab, on your own laptop (Mac or Linux)

The lab PCs have no C compiler, so the reference numbers must be made beforehand. You need the
repository (main branch), Python 3 and a C compiler (Mac: `xcode-select --install`;
Linux: `sudo apt install build-essential`).

### 2.1 Install the sender's Python packages

In a terminal, inside the repository folder:
```bash
python3 -m pip install -r sw/sender/requirements.txt
```
This installs `pyserial` (talks to COM ports) and `imageio-ffmpeg`, which includes its own copy of
**ffmpeg** (an audio converter), so you do not need to install ffmpeg separately.

### 2.2 Make the test file

The board accepts **only 48 kHz, mono** MP3 files. Any song works as a source (WAV, FLAC or MP3).
Find the bundled ffmpeg and convert:
```bash
FFMPEG=$(python3 -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())")
"$FFMPEG" -i any_song.wav -t 20 -ar 48000 -ac 1 -b:a 56k test_56k.mp3
```
- `-t 20` keeps the first 20 seconds (about 140 KB, about 6 s to send). Leave it out for the whole song.
- `-ar 48000` = 48 kHz, `-ac 1` = mono, `-b:a 56k` = 56 kbit/s.

Do **not** use `build/clip.mp3` from earlier tests: it is 44.1 kHz and the board rejects it.

### 2.3 Get the reference numbers

```bash
mkdir -p build
gcc -O2 -o build/decode_pc sw/app/main_host.c sw/app/decode.c -lm
build/decode_pc test_56k.mp3 build/test_56k.raw
```
It prints six lines. A real run on a 20 s clip gave these; your values will differ unless you
use the same song:
```
fnv1a(mp3) = 0x3048a002
res.channel_count = 1
res.frame_count = 836
res.sample_rate = 48000
res.samples_per_channel = 963072
res.checksum = 0xd8f3c471
```
What each line means:

| Line | Meaning | Must be |
|---|---|---|
| `fnv1a(mp3)` | Fingerprint of the **MP3 file's bytes**. The board recomputes it from the bytes it received. | Same on the board: proves the file arrived intact |
| `res.channel_count` | 1 = mono, 2 = stereo | `1` |
| `res.frame_count` | Number of MP3 frames (small chunks, about 24 ms each at 48 kHz) | Same on the board |
| `res.sample_rate` | Samples per second | `48000` |
| `res.samples_per_channel` | Total audio samples decoded | Same on the board |
| `res.checksum` | Fingerprint of the **decoded audio** | Same on the board: proves the ARM decoded it identically |

**Write all six numbers down** (there is a table in `lab_checklist_2026-11-05.md`), and copy
`test_56k.mp3` to a USB stick.

---

## 3. Set up the lab PC (once per PC)

### 3.1 Get the code

Open https://github.com/swarneel123bh-ux/FPGA-Project in a browser. Check the branch selector says
**main**. Click the green **Code** button → **Download ZIP**. Unzip it to a short path, e.g.
`C:\work\FPGA-Project`. (If git is installed, `git clone` works too.)

Copy `test_56k.mp3` from your USB stick into that folder.

### 3.2 Open Command Prompt in that folder

Open the folder in File Explorer, click the address bar, type `cmd`, press Enter. A black
Command Prompt window opens, already in the right folder.

### 3.3 Install the Python packages

```
py -m pip install --user -r sw\sender\requirements.txt
```
- If it says `'py' is not recognized`, try `python` instead of `py`.
- If neither works, Python is not installed: ask the lab staff.
- It needs internet access. It should end with `Successfully installed ...`.

---

## 4. Set up the board

Do this with the power **off**.

### 4.1 Find the parts

| Part | What it looks like / where |
|---|---|
| **SW8** | Power switch, next to the black barrel power socket |
| **J20** | Barrel socket for the 12 V power adapter |
| **J17 "PROG"** | Micro-USB socket for JTAG |
| **J14 "UART"** | Micro-USB socket for the serial link |
| **JP7–JP11** | A row of five 3-pin jumpers next to the SD-card slot: the **boot-mode jumpers** |
| **LD13** | Green LED: power is good |
| **LD12** | Blue LED ("DONE"): the FPGA has been configured. **It stays off in this test**, which is normal (we do not load an FPGA design) |

### 4.2 Set the boot-mode jumpers to JTAG

Each of JP7–JP11 has three pins and one small plastic cap (a "shunt") that connects the middle pin
to one side. One side is marked **GND**, the other **3V3**. The board reads these five jumpers at
power-up to decide where to start from.

For this test, **all five caps go on the GND side**:

| Jumper | Set to | What it controls |
|---|---|---|
| JP7  | GND | JTAG chain mode |
| JP8  | GND | boot device, bit 0 |
| JP9  | GND | boot device, bit 1 |
| JP10 | GND | boot device, bit 2 |
| JP11 | GND | PLL (clock) enabled |

All on GND means **"boot from JTAG"**: the board waits for Vitis to load a program. For
comparison, SD-card boot has JP9 and JP10 on 3V3. The board's printed labels next to the jumpers
are the final word: if they disagree with this table, follow the board and tell the team.

If **JP6** has a cap on it, leave it as it is.

### 4.3 Connect and power on

1. Plug the 12 V adapter into **J20** and into the wall socket.
2. Cable 1: micro-USB into **J17 (PROG)**, other end into the PC.
3. Cable 2: micro-USB into **J14 (UART)**, other end into the PC.
4. Slide **SW8** to **ON**. The green **LD13** must light. If it does not, switch off and on again;
   if it still stays off, the power adapter or board is faulty: tell the lab staff.

Windows may play the "device connected" sound twice, once per cable.

---

## 5. Find the board's COM port

1. Press **Win + X** and choose **Device Manager**.
2. Expand **Ports (COM & LPT)**.
3. Unplug the **J14** cable, wait two seconds, plug it back in. Watch the list: the entry that
   disappears and comes back is the board. It is usually called **USB Serial Port (COM5)** (the
   number varies). **Write the number down.**

Nothing appears under Ports?
- Reseat the J14 cable at both ends (it is often loose) and try another USB socket on the PC.
- Look under **Other devices** for an entry with a yellow warning sign, like "USB-UART": the
  Cypress USB-UART driver is missing. Installing it needs admin rights: ask the lab staff.

The J17 cable does not show up under Ports. That is normal.

---

## 6. Build the program in Vitis (once per PC, about 10 minutes)

### 6.1 Start Vitis and make a workspace

1. Start menu → **Xilinx Design Tools → Vitis 2020.2** (the version must be 2020.x).
2. It asks for a **workspace** (a folder where Vitis keeps its projects). Type a new, empty folder,
   e.g. `C:\work\zed_ws`, and click **Launch**. Do **not** use the repository folder.
3. Close the "Welcome" tab if it opens.

### 6.2 Create the project

1. **File → New → Application Project**. Click **Next** on the first page.
2. **Platform** page: click the tab **Create a new platform from hardware (XSA)**. Click **Browse**
   and open:
   `C:\Xilinx\Vitis\2020.2\data\embeddedsw\lib\fixed_hwplatforms\zed.xsa`
   This is Xilinx's ready-made description of the ZedBoard. If the folder is missing, search
   `C:\Xilinx` for `zed.xsa`, or ask the team. Click **Next**.
3. **Application project details**: Application project name `goal2_app`. Leave the rest. **Next**.
4. **Domain**: Operating System **standalone**, Processor **ps7_cortexa9_0**. **Next**.
5. **Templates**: choose **Empty Application** (the C one, not C++). **Finish**.

Vitis now builds the platform; the first time this takes a few minutes (watch the Console at the
bottom). Wait until it stops.

### 6.3 Add our source files

1. In the **Explorer** pane on the left, expand **goal2_app_system → goal2_app** and find the
   **src** folder.
2. Right-click **src → Import Sources...**
3. **From directory**: Browse to the repository's `sw\app` folder, e.g. `C:\work\FPGA-Project\sw\app`.
4. Tick these six files: `decode.c`, `decode.h`, `main_host.c`, `minimp3.h`, `uart_rx.c`,
   `uart_rx.h`. Click **Finish**. If it asks to overwrite anything, say **Yes**.

These are **copies**. If someone changes the files in the repository later, import them again.

### 6.4 Tell the compiler it is building for the board

`main_host.c` contains two versions of the program: one for the PC and one for the board. A
setting called `BOARD` selects the board version.

1. Right-click **goal2_app** (the project, not `src`) → **Properties**.
2. Go to **C/C++ Build → Settings**. On the **Tool Settings** tab, open
   **ARM v7 gcc compiler → Symbols**.
3. Next to **Defined symbols (-D)** click the small **+** icon, type `BOARD`, click **OK**.
4. Click **Apply and Close**.

### 6.5 Give the program enough stack memory

The MP3 decoder needs about 17 KB of working memory (stack); Vitis gives 8 KB by default, and the
board would crash in the decoder.

1. In **src**, double-click **lscript.ld**. A form opens.
2. Find **Stack Size** and change it from `0x2000` to `0x10000` (64 KB).
3. Save with **Ctrl + S**.

### 6.6 Build

Right-click **goal2_app → Build Project** (or click the hammer icon). Watch the **Console** tab at
the bottom. It must end with a line like:
```
Finished building: goal2_app.elf
```
Errors? See the table in section 9. Warnings inside `minimp3.h` are harmless.

---

## 7. Run the test

**Order matters.** The board prints its "I'm ready" message (`**Ready**`) only once, the moment the
program starts. The sender must already be listening, so **start the sender first, then the board**.

### 7.1 Start the sender

In the Command Prompt from section 3.2 (replace `COM5` with your number from section 5):
```
py sw\sender\send_mp3.py COM5 test_56k.mp3
```
It now waits silently for up to **60 seconds**. Go straight to the next step.

### 7.2 Start the program on the board

In Vitis: right-click **goal2_app → Run As → Launch Hardware (Single Application Debug)**. The exact
name varies a little between 2020.1 and 2020.2; pick the one that starts with **Launch** and
mentions **Hardware**. If it asks which configuration to use, accept the default.

Vitis resets the ARM, loads `goal2_app.elf` over JTAG (cable 1) and starts it. The Vitis Console
shows progress; the board's own output appears in the **Command Prompt**, not in Vitis.

### 7.3 Watch the Command Prompt

Within a few seconds it prints `sending ... bytes`, then (6 s for a 20 s clip) the board's report:
```
sending 140666 bytes, fnv 0x3048a002
rx: 140666 bytes, 0 uart errors, fnv 0x3048a002 (sender 0x3048a002)
res.channel_count = 1
res.frame_count = 836
res.sample_rate = 48000
res.samples_per_channel = 963072
res.checksum = 0xd8f3c471
decode 1234 ms for 20064 ms of audio (x16 real time)
```
(These are the example file's numbers from section 2.3; the timing on the last line is made up,
because nobody has run it on the board yet. Yours must match **your** numbers from section 2.3.)

The last line says how fast the ARM decodes: `x16 real time` means 20 s of audio took 1.2 s.
Anything above `x1` is fast enough to play live.

### 7.4 To run again

Start the sender again (7.1), then **Launch Hardware** again (7.2). You do not need to rebuild
unless the code changed.

---

## 8. Pass or fail

Compare with the numbers from section 2.3:

| Check | Pass |
|---|---|
| `uart errors` on the `rx:` line | `0` |
| the two fnv values on the `rx:` line | equal to each other, and equal to your `fnv1a(mp3)` |
| `res.frame_count`, `res.samples_per_channel` | equal to your numbers |
| `res.sample_rate` / `res.channel_count` | `48000` / `1` |
| `res.checksum` | equal to your number |
| the last line | contains `real time` and no `[FAIL]` |

If **everything matches except `res.checksum`**, the transfer is still proven correct. A tiny
floating-point rounding difference between the laptop's processor and the ARM can change the
audio fingerprint. Write both values down and report it; it needs a closer look, not a re-run.

Write the results into the table in `lab_checklist_2026-11-05.md`.

---

## 9. If something goes wrong

Read the **first** error message; later ones are often caused by it.

| What you see | Likely cause | Fix |
|---|---|---|
| Green LD13 does not light | No power | Check the adapter in J20 and the wall; toggle SW8 |
| Vitis: "no targets found", "Could not connect", or any JTAG error | Cable 1 not in J17, board off, jumpers not on JTAG, or the JTAG cable driver is missing | Check J17, LD13 and section 4.2; power-cycle the board and try again. If it still fails, ask the lab staff whether the Xilinx cable drivers are installed |
| `could not open port 'COM5'` or `Access is denied` | Another program has the port open, or the number is wrong | Close PuTTY / Tera Term / Vitis Serial Terminal; recheck the number in Device Manager |
| `Hang: Never got **Ready**` | Sender started after the board, wrong COM number, or cable 2 not in J14 | Start the sender first, then Launch Hardware again (section 7) |
| `[FAIL] header timeout` | Board got nothing | Check cable 2 and the COM number |
| `[FAIL] bad magic` | The first bytes were wrong | Run again (7.4); if it repeats, report it |
| `[FAIL] payload timeout, got X of Y bytes` | Part of the file never arrived | Note X and Y, run again; if it repeats, report it |
| `uart errors` above `0` | Bytes were lost or damaged in the receiver | Write down the number and the file size: that is a real bug to fix |
| `[FAIL] checksum mismatch` | The file arrived damaged | Run again; if it repeats, report both fnv values |
| `[FAIL] length ... out of range` | File too big (limit 2 MB) | Use a shorter clip (`-t 20` in section 2.2) |
| `[FAIL] need 48 kHz mono` | Wrong test file | Use the file made in section 2.2. For a quick demo only, add `--to48k` to the sender command |
| Output stops after the `rx:` line, nothing more | Stack too small: the decoder crashed | Section 6.5, then rebuild (6.6) and run again |
| Build error `BOARD` code missing / errors about `fopen` or `argv` | `BOARD` symbol not set | Section 6.4 |
| Build error `xil_printf.h: No such file` | Project was not made from `zed.xsa` with standalone | Redo section 6.2 |
| Build error `undefined reference to` a maths function (`sqrt`, `pow`, ...) | Maths library not linked | Properties → C/C++ Build → Settings → ARM v7 gcc linker → Libraries → **+** → `m` |
