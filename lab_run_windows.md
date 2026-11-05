# Lab run on Windows: send an MP3 to the ZedBoard and decode it

*Written by Claude as a lab guide (not graded team code). Vivado/Vitis 2020.2 on the lab's Windows PCs.*

Goal of this run: the laptop sends an MP3 over USB, the ARM receives it with zero lost bytes,
decodes it, and prints the result. No sound yet (that needs A's I2S output).

## How one PC talks to the board: two cables, two jobs

The board has **two micro-USB sockets**. Plug **both** into the same PC. They do different jobs
and never share a connection.

```
                  ┌── cable 1 → J17 "PROG" (JTAG) ── Vitis loads the program into the ARM
   lab PC ────────┤
                  └── cable 2 → J14 "UART" (COMn) ── send_mp3.py sends the song, reads the replies
```

- **JTAG (J17)** is used only by Vivado/Vitis. Windows shows no COM port for it, and you never
  choose a port: Vitis finds the board on its own.
- **UART (J14)** shows up as a COM port, e.g. `COM5`. The sender script opens it.
  Only **one** program can open a COM port at a time, so do not open PuTTY, Tera Term or the
  Vitis serial terminal while the sender runs. The sender prints everything the board says.

## Before the lab (on your own laptop)

1. Make the test file. The board plays **48 kHz mono** only:
   ```bash
   ffmpeg -i master.wav -ar 48000 -ac 1 -b:a 56k test_56k.mp3
   ```
2. Decode it on the laptop and write down the two numbers it prints, `fnv1a(mp3)` and
   `res.checksum`. The lab PC has no C compiler, so this has to happen before you go:
   ```bash
   mkdir -p build
   gcc -O2 -o build/decode_pc sw/app/main_host.c sw/app/decode.c -lm
   build/decode_pc test_56k.mp3 build/test_56k.raw
   ```
3. Copy `test_56k.mp3` to a USB stick or upload it somewhere you can reach from the lab.

## Step 1: Set up the lab PC (once per PC)

1. Get the code: download the repository from GitHub (green **Code** button → **Download ZIP**,
   then unzip), or `git clone` it if git is installed. Use the **main** branch.
2. Open **Command Prompt** in the repository folder and install the sender's Python packages:
   ```
   py -m pip install -r sw\sender\requirements.txt
   ```
   If `py` is not found, try `python`. If Python is missing, ask the lab staff.

## Step 2: Set up the board

1. Power switch **off**.
2. Boot-mode jumpers to **JTAG** (the five MIO jumpers next to the SD-card slot; the JTAG setting is
   printed on the board).
3. Cable 1 into **J17 (PROG)**, cable 2 into **J14 (UART)**, both to the PC.
4. Power switch **on**. The green power LED lights.

## Step 3: Find the COM port

1. Press **Win + X** → **Device Manager** → expand **Ports (COM & LPT)**.
2. Unplug the J14 cable and plug it back in. The entry that disappears and comes back is the board,
   usually "USB Serial Port (COM5)". Write the number down.
3. Nothing appears? The Cypress USB-UART driver is missing. Reseat the cable, try another USB port,
   and if it still does not appear, ask the lab staff to install the driver (it needs admin rights).

## Step 4: Build the program in Vitis (once per PC)

1. Start **Vitis 2020.2**. Choose a new, empty workspace folder, e.g. `C:\work\zed_ws`.
2. **File → New → Application Project → Next**.
3. Tab **Create a new platform from hardware (XSA)** → **Browse** →
   `C:\Xilinx\Vitis\2020.2\data\embeddedsw\lib\fixed_hwplatforms\zed.xsa` → **Next**.
4. Application name `goal2_app`. Processor **ps7_cortexa9_0**, operating system **standalone** →
   **Next** → template **Empty Application (C)** → **Finish**.
5. In the Explorer pane, right-click **goal2_app → src → Import Sources**. From directory:
   the repository's `sw\app` folder. Tick all six files (`decode.c`, `decode.h`, `main_host.c`,
   `minimp3.h`, `uart_rx.c`, `uart_rx.h`) → **Finish**. These are copies: edit the files in the
   repository, then import them again.
6. Right-click **goal2_app → Properties → C/C++ Build → Settings → ARM v7 gcc compiler → Symbols**.
   Under *Defined symbols* click **+** and add `BOARD` → **Apply and Close**.
7. Open `src\lscript.ld`, set **Stack Size** to `0x10000` and save. The MP3 decoder needs about
   17 KB of stack and the default is 8 KB; without this the board crashes in the decoder.
8. Click the hammer (**Build**). The console must end with `Finished building: goal2_app.elf`.

## Step 5: Run it

The board prints `**Ready**` only once, right after it starts, so **the sender goes first**.

1. In Command Prompt (replace `COM5` with your port):
   ```
   py sw\sender\send_mp3.py COM5 test_56k.mp3
   ```
   It waits up to 60 s for the board.
2. Within those 60 s, in Vitis: right-click **goal2_app → Run As → Launch Hardware**
   (the item is called *Launch on Hardware* in some 2020.x versions).
3. Command Prompt shows something like:
   ```
   sending 140627 bytes, fnv 0x…
   rx: 140627 bytes, 0 uart errors, fnv 0x… (sender 0x…)
   res.channel_count = 1
   res.frame_count = …
   res.sample_rate = 48000
   res.samples_per_channel = …
   res.checksum = 0x…
   decode … ms for … ms of audio (x… real time)
   ```
   At 230,400 baud, sending takes about 6 s per 140 KB.

To run again: start the sender first, then **Launch Hardware** again.

## Step 6: Pass or fail

| Check | Pass |
|---|---|
| `uart errors` | `0` |
| the two `fnv` values on the `rx:` line | equal |
| `res.checksum` | equal to the laptop's number from "Before the lab" |
| `res.sample_rate` / `res.channel_count` | `48000` / `1` |

If everything matches except `res.checksum`, the UART link is fine. Write down both numbers and
compare `frame_count` and `samples_per_channel`; a tiny rounding difference between the laptop's
and the ARM's floating-point maths can change the checksum.

Write the results in the table in `lab_checklist_2026-11-05.md`.

## If something goes wrong

| What you see | Likely cause | Fix |
|---|---|---|
| Vitis: no hardware target / JTAG error | Cable in the wrong socket, board off, or jumpers not on JTAG | Check J17, the power LED and the jumpers; in Vivado, *Open Hardware Manager → Auto Connect* should show `xc7z020` |
| `could not open port 'COM5'` / Access denied | Another program has the port open | Close PuTTY, Tera Term and any Vitis serial terminal |
| `Hang: Never got **Ready**` | Sender started after the board, wrong COM number, or cable 2 not in J14 | Check the port, start the sender, then Launch Hardware again |
| `[FAIL] header timeout` or `payload timeout` | Bytes not arriving | Check the cable and the COM number; make sure nothing else has the port open |
| `uart errors` above 0 | Bytes lost in the receiver | Write down the number and the file size; that is a real bug to fix |
| `[FAIL] checksum mismatch` | The file arrived corrupted | Run again; if it repeats, report the two fnv values |
| `[FAIL] need 48 kHz mono` | Wrong test file | Use `test_56k.mp3`, or add `--to48k` (demo only, not for measurements) |
| Output stops after the `rx:` line | Stack too small; the decoder crashed | Step 4.7: Stack Size `0x10000`, build again |
| Build error `undefined reference to` a maths function | Maths library not linked | Properties → C/C++ Build → Settings → ARM v7 gcc linker → Libraries → add `m` |
