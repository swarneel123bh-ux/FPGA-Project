# Briefing: member A's week-1 scope (codec, I2C, I2S)

Prepared 4 Nov 2026 for the lab meeting on Thu 5 Nov. Purpose: whoever does A's week-1 work
(Aarav, or Swarneel if the team agrees) starts from verified facts instead of a blank page.
Everything below is either from Digilent's official ZedBoard pin file or decoded from a
**known-working ZedBoard audio design** (sources at the end). Points marked **CHECK** must be
confirmed in the ADAU1761 datasheet before relying on them.

## 1. What has to exist, and who is waiting for it

From `docs/plan/A-aarav-codec-fsm.md`, week 1:

| File | Does | Unblocks |
|---|---|---|
| `rtl/codec_cfg.v` | I2C master + ROM of register writes; configures the ADAU1761 at power-up | Everything (no sound without it) |
| `rtl/i2s_rx.v` | ADC samples in → `x_ref`, `e_err` (s24), `sample_tick` (1-cycle pulse, 48 kHz) | B (FxLMS), C (path ID, meter), D (FIFO read) |
| `rtl/i2s_tx.v` | `dac_out` (s24) → DAC, latched on `sample_tick` | Everyone's output; D's music |
| `constraints/zedboard.xdc` | Pins and clock | Any bitstream |

**Exit (Fri 6 Nov):** on hardware, mic → headphone passthrough with **both** mics heard.

Interface rules (`docs/plan/README.md` §5): one clock `clk` = 100 MHz, `rst` active-high
synchronous, `sample_tick` one-cycle pulse at 48 kHz, samples `signed [23:0]`.

## 2. ZedBoard pins (verified: Digilent `Zedboard-Master.xdc`)

All in **bank 13, LVCMOS33** (`set_property IOSTANDARD LVCMOS33 [get_ports -of_objects [get_iobanks 13]]`).

| Board net | FPGA pin | Direction in the working design | Use |
|---|---|---|---|
| GCLK | Y9 | in | 100 MHz board clock |
| AC-MCLK | AB2 | FPGA → codec | Codec master clock, **24 MHz** |
| AC-SCK | AB4 | FPGA → codec | I2C clock |
| AC-SDA | AB5 | **inout** (open drain) | I2C data |
| AC-ADR0 | AB1 | FPGA → codec | I2C address pin, drive **1** |
| AC-ADR1 | Y5 | FPGA → codec | I2C address pin, drive **1** |
| AC-GPIO0 | Y8 | FPGA → codec | I2S data **to the DAC** (playback) |
| AC-GPIO1 | AA7 | codec → FPGA | I2S data **from the ADC** (record) |
| AC-GPIO2 | AA6 | codec → FPGA | **BCLK** (codec is clock master) |
| AC-GPIO3 | Y6 | codec → FPGA | **LRCLK** (codec is clock master) |

Note: Digilent's file names GPIO2/GPIO3 `BCLK_O`/`LRCLK_O` (FPGA outputs, i.e. codec as slave).
The working design below does the opposite: **codec is master, FPGA reads BCLK/LRCLK**. Either
works if the codec register `0x4015` matches; pick one and make the `.xdc` directions agree.

## 3. The proven architecture (from the working design)

```
GCLK 100 MHz ─► MMCM ─► 48 MHz ─► ÷2 ─► AC-MCLK 24 MHz ─► ADAU1761 PLL ─► 49.152 MHz core (1024 × 48 kHz)
                                                              │
                                     codec drives BCLK (64 × fs = 3.072 MHz) and LRCLK (48 kHz)
                                                              │
FPGA (100 MHz): sample BCLK/LRCLK as ordinary inputs, detect edges, shift data in/out
                → one "new sample" pulse per LRCLK frame = sample_tick
```

Why this is a good fit for our plan: the FPGA never runs logic on BCLK, so **everything stays
in the single 100 MHz clock domain** the interface table requires. 100 MHz samples the
3.072 MHz BCLK about 32 times per period: plenty. Pass BCLK, LRCLK and ADC data through a
two-flop synchroniser before using them (they come from another clock).

MCLK accuracy: with the codec as master, the sample rate is exactly 48 kHz × (MCLK / 24 MHz).
A small MCLK error only shifts fs slightly; it does not break anything.

## 4. I2C configuration (decoded from the working design)

- Device address: **7-bit 0x3B** (write byte **0x76**), because ADR0 = ADR1 = 1.
- Every write: `START, 0x76, 0x40, <reg low byte>, <data bytes...>, STOP`. Registers are 16-bit
  addresses `0x40xx`; the PLL register takes 6 data bytes in one write.
- Order matters: clock first, wait for the PLL, then the rest.

| # | Register | Value | Meaning (CHECK bit fields in datasheet) |
|---|---|---|---|
| 1 | 0x4000 clock control | 0x0E | Select PLL as clock source, core clock still off |
| 2 | 0x4002 PLL control (6 bytes) | 00 7D 00 0C 23 01 | M = 125, N = 12, R = 4, X = 2, fractional mode, PLL enable → 24 MHz / 2 × (4 + 12/125) = **49.152 MHz** |
| — | wait | | Until PLL locked (datasheet: lock bit in the PLL register; the reference just waits) |
| 3 | 0x4000 | 0x0F | Core clock enable |
| 4 | 0x4015 serial port 0 | 0x01 | **Codec = I2S master** (drives BCLK/LRCLK) |
| 5 | 0x400A / 0x400B | 0x01 / 0x05 | Left record mixer on / left line-input gain |
| 6 | 0x400C / 0x400D | 0x01 / 0x05 | Right record mixer on / right line-input gain |
| 7 | 0x401C / 0x401E | 0x21 / 0x41 | Left / right playback mixers: DAC on |
| 8 | 0x4023 / 0x4024 | 0xE7 / 0xE7 | Headphone left / right volume, unmuted |
| 9 | 0x4025 / 0x4026 | 0xE7 / 0xE7 | Line-out left / right volume |
| 10 | 0x4019 ADC control | 0x03 | Both ADCs on |
| 11 | 0x4029 playback power | 0x03 | Playback path powered |
| 12 | 0x402A DAC control | 0x03 | Both DACs on |
| 13 | 0x40F2 / 0x40F3 | 0x01 / 0x01 | Serial input → DAC, ADC → serial output routing |
| 14 | 0x40F9 clock enable 0 | 0x7F | Enable internal clocks |
| 15 | 0x40FA clock enable 1 | 0x03 | Enable clock generators |

**This configures LINE IN → HEADPHONES, not the mics.** It is the right first step (it proves
MCLK, I2C, PLL and I2S all work), but for the project the record path must be changed to the
**mic inputs**, with mic bias (register `0x4010`) and the mic PGA settings (`0x400E`/`0x400F`).
CHECK those in the datasheet. This ties into A's open question: ZedBoard jumper JP1 gives mic
bias to the **right channel only**, so the second mic's bias is still undecided (options in
A's plan, week 1 point 3).

## 5. I2S frame (from the working design; CHECK against the datasheet's serial port timing)

- 64 BCLK per LRCLK frame: two 32-bit slots, left then right.
- Each slot: 24-bit sample, **MSB first**, then 8 padding bits.
- Data changes on one BCLK edge and is sampled on the other; the reference shifts input on the
  falling-edge detection and output on the rising-edge detection of the (delayed) BCLK.
- On the LRCLK rising edge it latches both received samples, loads the next two to send and
  pulses `new_sample` → that pulse is our **`sample_tick`**.
- Which channel carries which mic (`x_ref` = reference, `e_err` = error) must be agreed with B/C.

## 6. Suggested order (one day of work to first sound)

1. `.xdc` with the pins above; MMCM (Clocking Wizard) 100 → 48 MHz; ÷2 → AC-MCLK.
2. `codec_cfg.v`: a small I2C master (100–400 kHz SCL from 100 MHz) + a ROM of the writes in §4.
   Testbench: check start, address byte 0x76, ACK slots, data, stop for each write.
3. `i2s_rx.v` / `i2s_tx.v`: synchronise BCLK/LRCLK/data, edge-detect, shift registers.
   Testbench: a behavioural codec that drives BCLK/LRCLK and known samples; check they come
   out unchanged and `sample_tick` is one cycle wide.
4. Hardware step 1: **line in → headphones** loopback (`i2s_tx` sends what `i2s_rx` received).
   If you hear the phone/laptop audio, clocks, I2C and I2S all work. Use an ILA on
   `sample_tick` and the samples.
5. Hardware step 2: switch the record path to the mics (register changes only) → the Friday exit.

Debugging tips: if there is no sound at all, check with an ILA that BCLK and LRCLK toggle
(they only appear after the PLL and serial port are configured, so no BCLK = I2C/config
problem). If I2C gets no ACK, check the address (0x76) and that ADR0/ADR1 are driven high.

## 7. Using the reference design

`ems-kl/zedboard_audio` (TU Kaiserslautern, based on Mike Field's design) is VHDL and the
repository shows **no licence**: read it to understand the sequence and timing, but do not copy
its code into our deliverables. The team writes its own Verilog (graded project).

## Sources

- Digilent ZedBoard master constraints:
  https://github.com/Digilent/digilent-xdc/blob/master/Zedboard-Master.xdc
- Working reference design (VHDL; files read: `adau1761_configuraiton_data.vhd`,
  `adau1761_izedboard.vhd`, `clocking.vhd`, `i2s_data_interface.vhd`):
  https://github.com/ems-kl/zedboard_audio
- Its documentation (Stefan Scholl, TU Kaiserslautern; also linked in A's plan):
  https://kluedo.ub.rptu.de/files/4034/zedboard_audio_doc.pdf
- ADAU1761 datasheet (register map, PLL, serial port timing, mic bias):
  https://www.analog.com/media/en/technical-documentation/data-sheets/ADAU1761.pdf
- ADI Linux driver docs (PLL = 1024 × fs, I2C address depends on ADDR0/ADDR1):
  https://analogdevicesinc.github.io/linux/drivers/sound/adau1361.html
