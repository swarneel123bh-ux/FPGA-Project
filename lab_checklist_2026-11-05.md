# Lab meeting: Thu 5 Nov 2026, 1 pm

Week-1 exit is **Fri 6 Nov**; feature freeze **Thu 12 Nov**.

## Before leaving

- [ ] `git pull` on `d/goal2`
- [ ] `pip install -r sw/sender/requirements.txt` on the laptop
- [ ] Make two 48 kHz mono test MP3s (56k and 128k):
      `ffmpeg -i master.wav -ar 48000 -ac 1 -b:a 56k test_56k.mp3`
- [ ] Run each through the PC decoder and write down the numbers:
      `build/decode_pc test_56k.mp3 build/test_56k.raw`

| File | `fnv1a(mp3)` | `res.checksum` |
|---|---|---|
| test_56k.mp3 | | |
| test_128k.mp3 | | |

- [ ] Pack: laptop, 2 micro-USB cables, headphones

## Team agenda

- [ ] **Aarav (A): codec I2C, I2S RX/TX, passthrough status.** Nothing pushed yet; both
      Friday exits depend on it. If stuck, decide who helps.
- [ ] **Clock:** all PL logic on `FCLK_CLK0` = 100 MHz, including the AXI clock of
      `music_fifo_axi`. `sample_tick` is a one-cycle pulse from `i2s_rx`.
- [ ] **Show Aarav the `music_fifo_axi` ports:** `sample_tick` in; `music_raw` (s24) and
      `fifo_underrun` out. Music is 48 kHz mono.
- [ ] **Samarth (C):** restore his files onto his own branch (`rtl/`, `sim/`) from commit
      `be4364d` or `7e79633`; check that `tb_sec_path_id` finishes.
- [ ] Agree branch names and **pull requests into `main`** (Aadyant and Swarneel have tested
      blocks ready).
- [ ] Who keeps the Vivado project / rebuild Tcl script (plan says Aarav)
- [ ] **Instructor ANC question** (overdue): active anti-noise through a speaker, or cleaning a
      recording? Ask if she is there; record the answer in `docs/plan/README.md`.
- [ ] **Book the demo slot** (17–25 Nov; Swarneel away 26–30 Nov)

## On the board (Swarneel)

- [ ] Check the lab's Vitis version (expect 2020.x)
- [ ] Vitis: platform from `zed.xsa`, standalone on `ps7_cortexa9_0`, Empty Application (C),
      import `sw/app/` files
- [ ] Define **`BOARD`** (C/C++ Build Settings → Symbols)
- [ ] **Stack size `0x10000`** in `src/lscript.ld` (decoder crashes otherwise)
- [ ] Board: JTAG boot jumpers, both micro-USB cables, power on
- [ ] Start the sender **first**, then Run As → Launch on Hardware:
      `python3 sw/sender/send_mp3.py /dev/ttyACM0 test_56k.mp3` (Windows: `COM3` etc.)
- [ ] No serial terminal open on the same port

Record:

| File | UART errors | FNV match | `res.checksum` = PC? | Real-time factor | Transfer time |
|---|---|---|---|---|---|
| test_56k.mp3 | | | | | |
| test_128k.mp3 | | | | | |

- [ ] Negative test: a 44.1 kHz file must give `[FAIL] need 48 kHz mono`
- [ ] Afterwards: put the results into the handoff file

## Notes from the meeting

-
