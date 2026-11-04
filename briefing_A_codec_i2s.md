# Briefing: member A's week-1 scope (codec, I2C, I2S)

Prepared 4 Nov 2026 for the lab meeting on Thu 5 Nov. Purpose: whoever does A's week-1 work
(Aarav, or Swarneel if the team agrees) starts from verified facts instead of a blank page.
Everything below is either from Digilent's official ZedBoard pin file or decoded from a
**known-working ZedBoard audio design**, and every register, bit field and timing rule has been
**checked against the ADAU1761 datasheet, Rev. F** (table numbers given as "DS Table n").
What the datasheet cannot settle (how the ZedBoard wires its jacks) is marked **OPEN**.

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

## 4. I2C configuration (decoded from the working design, checked against the datasheet)

- Device address: the chip address is `0 1 1 1 0 ADDR1 ADDR0` (DS "I2C Port"), so with
  ADR0 = ADR1 = 1 it is **7-bit 0x3B**, write byte **0x76**.
- Every write: `START, 0x76, 0x40, <reg low byte>, <data bytes...>, STOP`. Registers are 16-bit
  addresses `0x40xx`.
- **Startup rules (DS "Startup, Initialization, and Power", Case 2: PLL is used):**
  - The PLL register is 48 bits and **must be written as all 6 bytes in one continuous write**.
  - While the PLL locks, **only 0x4000 and 0x4002 may be accessed**; writing anything else is
    prohibited until COREN and the lock bit are both set.
  - Lock time at 24 MHz MCLK (fractional): **2.95 ms typical** (DS Table 11). Either poll the
    lock bit (bit 1 of the last byte of 0x4002, read-only) or wait a safe margin, e.g. 10 ms.

| # | Register | Value | Meaning (bit fields from the datasheet) |
|---|---|---|---|
| 1 | 0x4000 clock control (DS Table 12) | 0x0E | CLKSRC = 1 (PLL), INFREQ = 11 (1024 × fS), COREN = 0 (core still off) |
| 2 | 0x4002 PLL control (DS Table 15) | 00 7D 00 0C 23 01 | M = 125, N = 12, R = 4, X = 2, Type = fractional, PLLEN = 1 → 24 MHz / 2 × (4 + 12/125) = **49.152 MHz**. Exactly the DS Table 17 entry for MCLK = 24 MHz, fS = 48 kHz (`0x007D 000C 2301`) |
| — | wait | | PLL lock (above) |
| 3 | 0x4000 | 0x0F | COREN = 1: core clock on |
| 4 | 0x4015 serial port 0 (DS Table 65) | 0x01 | MS = 1: **codec is master** (drives BCLK/LRCLK); other bits default (see §5) |
| 5 | 0x400A / 0x400C record mixer 1 / 2 control 0 | 0x01 / 0x01 | MX1EN / MX2EN = 1 (mixers on); single-ended LINP/LINN gains left at mute |
| 6 | 0x400B / 0x400D record mixer 1 / 2 control 1 | 0x05 / 0x05 | **AUX input** gain (MX1AUXG / MX2AUXG) = 0 dB; differential (mic) boost left at mute |
| 7 | 0x401C / 0x401E playback mixer 3 / 4 | 0x21 / 0x41 | Left DAC → left mixer unmuted (MX3LM) / right DAC → right mixer unmuted (MX4RM); mixers enabled |
| 8 | 0x4023 / 0x4024 headphone L / R (DS Table 93) | 0xE7 / 0xE7 | Volume 111001 = **0 dB**, unmuted (mute bit is active-low), HPEN = 1 |
| 9 | 0x4025 / 0x4026 line out L / R | 0xE7 / 0xE7 | Same encoding: 0 dB, unmuted |
| 10 | 0x4019 ADC control | 0x03 | ADCEN = 11: both ADCs on; ADC high-pass filter off |
| 11 | 0x4029 playback power | 0x03 | PREN = PLEN = 1: both playback channels on |
| 12 | 0x402A DAC control 0 | 0x03 | DACEN = 11: both DACs on |
| 13 | 0x40F2 / 0x40F3 serial routing | 0x01 / 0x01 | Serial input → DACs; ADCs → serial output (bypassing the on-chip DSP) |
| 14 | 0x40F9 clock enable 0 | 0x7F | All seven digital clock engines on (serial port, routing, (de)interpolator resync, ALC, slew) |
| 15 | 0x40FA clock enable 1 | 0x03 | Digital clock generators 0 and 1 on |

Row 6 means **the ZedBoard's LINE IN jack is wired to the codec's AUX inputs** (LAUX/RAUX):
that is the input this working design records from.

**This configures LINE IN → HEADPHONES, not the mics.** It is the right first step (it proves
MCLK, I2C, PLL and I2S all work). For the mics, these registers change (from the datasheet):

| Register | What to set for an analog electret mic |
|---|---|
| 0x4010 mic bias (DS Table 55) | MBIEN (bit 0) = 1 turns on the MICBIAS pin; MBI (bit 2): 0 = 0.90 × AVDD, 1 = 0.65 × AVDD; MPERF (bit 3) = 1 for more bias current |
| 0x400E / 0x400F differential input volume (DS Table 51) | LDEN/RDEN (bit 0) = 1 enables the differential PGA on LINP/LINN (RINP/RINN); LDMUTE/RDMUTE (bit 1) = 1 unmutes (active-low mute); volume [7:2]: 010000 = 0 dB, 0.75 dB per step, up to +35.25 dB |
| 0x400B / 0x400D | LDBOOST/RDBOOST [4:3]: 01 = 0 dB, 10 = +20 dB boost into the record mixer; set the AUX gain [2:0] back to mute so line-in does not mix in |

**OPEN (needs the ZedBoard schematic or user guide, not the datasheet):**
- Which codec pins the MIC IN jack is wired to (differential left/right inputs or single-ended).
- The codec has **one** MICBIAS pin; ZedBoard jumper JP1 routes it to the **right channel only**.
  So the second mic's bias is still A's open decision (options in A's plan, week 1 point 3).

## 5. I2S frame (checked against the datasheet)

With 0x4015 = 0x01 and 0x4016 at its default (DS Tables 65 and 67), the codec produces
standard I2S:

- **64 BCLK per LRCLK frame** (BPF = 000): BCLK = 64 × 48 kHz = **3.072 MHz**.
- **LRCLK 50 % duty**; the **left** channel frame starts on the LRCLK **falling** edge
  (LRPOL = 0), so LRCLK low = left, high = right.
- Data **changes on the BCLK falling edge** (BPOL = 0), so sample it on the **rising** edge.
- **1 BCLK delay** after the LRCLK edge before the MSB (LRDEL = 00), **MSB first** (MSBP = 0).
- Each 32-bit slot carries a 24-bit sample, MSB first, then padding.
- Converter rate 48 kHz (0x4017 default, CONVSR = 000 = fS).
- The working design latches both received samples on the LRCLK rising edge, loads the next
  two to send, and pulses `new_sample` → that pulse is our **`sample_tick`**.
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
- ADAU1761 datasheet, Rev. F, 92 pages (register map, PLL, serial port timing, mic bias; all
  register values above checked against it):
  https://www.analog.com/media/en/technical-documentation/data-sheets/ADAU1761.pdf
- ADI Linux driver docs (PLL = 1024 × fs, I2C address depends on ADDR0/ADDR1):
  https://analogdevicesinc.github.io/linux/drivers/sound/adau1361.html
