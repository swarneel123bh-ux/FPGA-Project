# Setup and how to run (goal 2 path)

What has to be installed before the goal-2 code (MP3 sender, ARM app, music FIFO) can be built,
simulated and run, and the commands for each step.

## 1. What to install

| Tool | Version | Needed for | Install |
|---|---|---|---|
| Vivado + Vitis | **2020.2** (lab version) | Synthesis, block design, ARM app | AMD Unified Installer 2020.2, product **Vitis** (includes Vivado and the ARM compiler); Zynq-7000 devices are enough |
| Python | 3.10 or newer | Sender script | python.org, or your OS package manager |
| Python packages | see `sw/sender/requirements.txt` | Sender: `pyserial`, and `imageio-ffmpeg`, which brings its own ffmpeg (no separate ffmpeg install) | `pip install -r sw/sender/requirements.txt` |
| Icarus Verilog | 11 or newer (`-g2012`) | Running the testbenches without Vivado | Linux: `sudo apt install iverilog`; Mac: `brew install icarus-verilog` |
| GTKWave | any | Viewing `.vcd` waveforms (optional) | `sudo apt install gtkwave` / `brew install --cask gtkwave` |
| C compiler | gcc or clang | PC build of the decoder, for checking results | Linux: `sudo apt install build-essential`; Mac: `xcode-select --install` |
| socat | any | Testing the sender without a board (Linux/Mac only) | `sudo apt install socat` / `brew install socat` |

Use Vivado/Vitis **2020.2** for anything that goes to the lab: projects made in a newer version
do not open in 2020.x. The source files themselves (`.v`, `.c`, `.py`) work in any version.

On Linux, to open the board's serial port without `sudo`, add yourself to the `dialout` group
once, then log out and back in:
```bash
sudo usermod -aG dialout $USER
```

## 2. Simulate the music FIFO (no board needed)

```bash
iverilog -g2012 -o sim/tb_music_fifo.vvp rtl/music_fifo.v sim/tb_music_fifo.v && vvp -n sim/tb_music_fifo.vvp
iverilog -g2012 -o sim/tb_music_fifo_axi.vvp rtl/music_fifo.v rtl/music_fifo_axi.v sim/tb_music_fifo_axi.v && vvp -n sim/tb_music_fifo_axi.vvp
```
Each prints `PASS` or `FAIL` at the end. Waveforms are written to `sim/*.vcd` (git-ignored).

## 3. Check an MP3 on the PC (no board needed)

```bash
gcc -O2 -o build/decode_pc sw/app/main_host.c sw/app/decode.c -lm
build/decode_pc song.mp3 build/song.raw
```
Prints the `fnv1a(mp3)` the sender will send and the decode results; the board must print the
same `res.checksum` for the same file. (`build/` is git-ignored; create it first.)

## 4. Make test MP3s

The board plays **48 kHz mono** only. For measurements, encode straight from the lossless master
(one lossy step):
```bash
ffmpeg -i master.wav -ar 48000 -ac 1 -b:a 56k test_56k.mp3
```
For a quick demo with any MP3, let the sender convert it instead (`--to48k`, below). That
re-encodes an already lossy file, so do not use it for measurements.

If you have no system ffmpeg, the one installed with the Python packages works too:
```bash
python3 -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())"
```

## 5. Build the ARM app (Vitis 2020.2)

1. Platform project from the ZedBoard hardware: `zed.xsa` from
   `<Vitis>/data/embeddedsw/lib/fixed_hwplatforms/` (until our own block design exists),
   standalone on `ps7_cortexa9_0`.
2. Empty Application (C) on that platform; import the files in `sw/app/`.
3. C/C++ Build Settings → Symbols: add **`BOARD`**.
4. In `src/lscript.ld`, set **Stack Size to `0x10000`**. The MP3 decoder needs 17.2 KB of stack
   and the default is 8 KB; without this the board crashes in the decoder.

## 6. Send an MP3 to the board

1. ZedBoard: JTAG boot jumpers, both micro-USB cables (PROG and UART) connected, power on.
2. Start the sender **first**; the board prints `**Ready**` only once:
   ```bash
   python3 sw/sender/send_mp3.py /dev/ttyACM0 test_56k.mp3            # Windows: COM3 etc.
   python3 sw/sender/send_mp3.py /dev/ttyACM0 any_song.mp3 --to48k    # demo only
   ```
3. In Vitis: Run As → Launch on Hardware.
4. Pass: `0 uart errors`, the two FNV values match, and `res.checksum` equals the PC build's.

Do not keep a serial terminal (Vitis, minicom, PuTTY) open on the same port while sending.

## 7. Test the sender without a board (Linux/Mac)

Make a linked pair of virtual serial ports, then run the fake board on one end and the sender on
the other, each command in its own terminal:
```bash
socat -d -d pty,raw,echo=0 pty,raw,echo=0          # prints two /dev/pts/N paths
python3 sw/sender/send_mp3.py /dev/pts/A test_56k.mp3
python3 sw/sender/fake_board.py /dev/pts/B --decoder build/decode_pc
```
