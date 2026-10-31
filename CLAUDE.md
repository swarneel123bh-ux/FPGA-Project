# FPGA Audio Enhancement (EEE F314, Group 16) — start here

ZedBoard (Zynq-7020) project: goal 1 is two-microphone feedforward FxLMS active noise
cancellation in the PL; goal 2 is treble restoration of low-bitrate MP3 decoded on the ARM.
Vivado 2020 / Vitis 2020.x.

**The team plan is in `docs/plan/`:** `README.md` (schedule, block interfaces, ANC algorithm,
rules) and one file per member (A–D). Ask which member you are working for, then read both.
Swarneel also keeps a private `HANDOFF.md` (git-ignored, full decision log); if it exists, read
its §1 and §12 too.

## Layout
```
rtl/          PL Verilog (team code)
sim/          testbenches and test vectors
model/        fixed-point Python golden models (ANC, treble restoration)
sw/           Vitis bare-metal ARM code (UART RX, MP3 decode, AXI feed)
constraints/  ZedBoard .xdc
docs/         report, diagrams, measurements
```

## Rules
- **Learning project, graded.** The team writes the deliverable RTL, testbenches and golden
  models. Claude reviews, catches bugs and argues architecture. Scaffolding is fine but must be
  marked as not team code (header comment), and never goes in `rtl/` unasked.
- **Interfaces** between members' blocks are fixed in `docs/plan/README.md` §5. Do not change
  them, or another member's files, without the member asking.
- **HANDOFF.md** (only where it exists): update with patch blocks through `./handoff_mgr.py apply`; run
  `./handoff_mgr.py ids HANDOFF.md` first. Never regenerate the whole file unless asked.
  STATUS values: NOT_STARTED, IN_PROGRESS, BLOCKED, COMPLETED, OPEN, CLOSED.
- **Web-verify** any tool, library or download before recommending it.
- **Git:** commit and push only when asked; work on the member's own branch, never straight to
  `main` (`docs/plan/README.md` §8). `HANDOFF.md` stays untracked.
- Claims in the report follow HANDOFF §3.4 (measured dB at the error mic; no "silence").
