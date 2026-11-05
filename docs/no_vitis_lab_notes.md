# Session handoff: running goal 2 ARM code when the lab has no Vitis

*Written by Claude (not team code) on 2026-11-05, to continue this work on Swarneel's Ubuntu
laptop. Branch: `claude/vitis-hls-without-ide-88e144`. Read `CLAUDE.md` and `docs/plan/` first
as usual; this file only covers the Vitis problem.*

## 1. The problem and what we found

| Fact | Detail |
|---|---|
| Lab PCs | Windows, **Vivado 2020.1** and **Vitis HLS 2020.1** only. `C:\Xilinx\Vitis` exists but is empty: no Vitis IDE, no XSCT, no ARM compiler. No machine in the lab has `xsct`. |
| Vitis HLS | Cannot help: it turns C into FPGA hardware, it does not build ARM programs. |
| Vivado 2020.1 | Cannot compile ARM code either. It *can* write the board's QSPI flash over JTAG, but that also needs a boot loader (`fsbl.elf`) built with Vitis. |
| Team | Only Swarneel's **Ubuntu laptop** has Vitis (version still to be confirmed: run `ls /tools/Xilinx/Vitis`). The Mac (Apple Silicon) cannot run Vitis. |
| SD card | The team has none. |
| HANDOFF.md §6 | Says "Lab tools: Vivado 2020 / Vitis 2020.x", which is wrong for Vitis. Not patched yet. |

Consequence: every ARM build happens on the Ubuntu laptop. Missing Vitis in the lab is a
project risk for goal 2 (ARM MP3 decoding) and should be raised with the team and instructor;
asking lab staff to finish the Vitis install ("Add Design Tools or Devices" in the 2020.1
installer) is the clean fix.

## 2. Three ways to get the program onto the board

| Route | Needs in the lab | Status |
|---|---|---|
| **A. Laptop + JTAG** (today) | The laptop itself, plugged into J17 and J14 | Ready; steps in section 4 below |
| **B. QSPI flash** (board runs without the laptop) | Vivado 2020.1 only | Scripts written, never run on real tools |
| C. SD card | Nothing (only Python for the sender) | Scripts written; no SD card available |

## 3. What is in this branch

| File | What | Tested? |
|---|---|---|
| `sw/xsct/build_boot.tcl` | XSCT: builds platform + FSBL from `zed.xsa`, imports `sw/app`, defines `BOARD`, links `m`, stack 0x10000, Release build, runs `bootgen`. Output in `build/sd/`: `BOOT.BIN`, `fsbl.elf`, `goal2_app.elf`. Run: `xsct sw/xsct/build_boot.tcl` | Dry run with stubbed XSCT only |
| `sw/xsct/run_jtag.tcl` | XSCT: `ps7_init` + download + run `goal2_app.elf` over JTAG (replaces "Launch Hardware") | Syntax only |
| `sw/xsct/program_qspi.tcl` | Vivado batch: writes `BOOT.BIN` into QSPI (`s25fl256s-3.3v-qspi-x4-single`, with `PROGRAM.ZYNQ_FSBL`). Run: `vivado -mode batch -source program_qspi.tcl -tclargs BOOT.BIN fsbl.elf` | Dry run with stubbed Vivado only |
| `lab_run_windows.md` | New note at top; section 10 (SD route), section 11 (QSPI route) | Not tried |

All scripts are marked NOT TEAM CODE. Known risks to check on first real run:
- `build_boot.tcl`: app template name (`Empty Application` vs `Empty Application(C)`; the script
  tries both); assumes `platform create` builds the FSBL by default; finds `fsbl.elf` by search.
- `program_qspi.tcl`: a ZedBoard user reported a flash-initialisation error writing the S25FL256S
  from Vivado 2018.3 (unresolved). Write the flash with jumpers on JTAG; if it fails, try other
  S25FL256S entries in the Vivado window.
- Boot-mode jumpers: JTAG all GND; SD = JP9+JP10 on 3V3 (JP6 on); QSPI = only JP10 on 3V3.

## 4. Do now on the Ubuntu laptop: route A, the IDE way

```bash
ls /tools/Xilinx/Vitis
source /tools/Xilinx/Vitis/<version>/settings64.sh
# JTAG cable driver, once per laptop (replug J17 after):
cd $XILINX_VITIS/data/xicom/cable_drivers/lin64/install_script/install_drivers && sudo ./install_drivers; cd ~
sudo apt install -y libtinfo5 libncurses5     # Vitis 2020.x on newer Ubuntu; 24.04 lacks libtinfo5
git clone https://github.com/swarneel123bh-ux/FPGA-Project.git ~/FPGA-Project
cd ~/FPGA-Project && git checkout claude/vitis-hls-without-ide-88e144
python3 -m venv .venv && . .venv/bin/activate && pip install -r sw/sender/requirements.txt
```

Board: JP7-JP11 all GND, power J20, J17 and J14 to the laptop, SW8 on. Port:
`ls /dev/ttyACM* /dev/ttyUSB*` (usually `/dev/ttyACM0`), then `sudo chmod a+rw /dev/ttyACM0`.

Vitis (`vitis &`): new workspace → Application Project from `zed.xsa`
(`$XILINX_VITIS/data/embeddedsw/lib/fixed_hwplatforms/zed.xsa`), name `goal2_app`, standalone,
`ps7_cortexa9_0`, Empty Application (C) → import the 6 files of `sw/app` → Properties: symbol
`BOARD`, library `m` → `lscript.ld` stack `0x10000` → Build. (Full steps: `lab_run_windows.md`
section 6, same on Linux.)

Run: `python sw/sender/send_mp3.py /dev/ttyACM0 test_audio/beethoven5_20s_48k_mono_56k.mp3`,
then within 60 s **Run As → Launch Hardware**. Pass: `0 uart errors`, fnv `0x6bbdb72d` twice,
frames `836`, samples `963072`, `48000` Hz, `1` ch, checksum `0xb5f37fd1`, no `[FAIL]`.
Only the checksum differing = transfer fine, report both values.

## 5. Next steps after today's test

1. On the laptop, try the script route: `xsct sw/xsct/build_boot.tcl`, then
   `xsct sw/xsct/run_jtag.tcl` (sender started first). Fix whatever breaks; this proves the
   scripts before they matter.
2. Carry `build/sd/BOOT.BIN`, `build/sd/fsbl.elf`, `sw/xsct/program_qspi.tcl` to the lab and
   try route B (`lab_run_windows.md` section 11), so the board runs without the laptop.
3. Patch HANDOFF.md (private, not in git; via `./handoff_mgr.py apply`): §6 lab tools row, §9 new
   risk "no Vitis in lab; only one Ubuntu laptop can build ARM code", §1 status.
4. Decide with the team whether to ask lab staff / instructor to install Vitis 2020.1.
5. Maybe add Ubuntu notes to the lab guide (port `/dev/ttyACM0`, `chmod`, cable driver).

## 6. Notes for the next Claude session

- Learning project: review, don't write deliverable code; scaffolding is marked and stays out of
  `rtl/`. Commit/push only when asked, never to `main`.
- `HANDOFF.md` lives only on the Mac (git-ignored). Copy it over by hand if it is needed on the
  laptop.
- Web-verify tools before recommending them (`CLAUDE.md`).
