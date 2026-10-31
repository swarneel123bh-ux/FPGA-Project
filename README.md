# FPGA-Based Audio Enhancement System (ZedBoard)

EEE F314 FPGA-Based System Design, BITS Pilani Hyderabad — Group 16, section P2.

1. **Active noise cancellation:** feedforward FxLMS in the PL with a reference and an error
   microphone, cancelling 100–500 Hz periodic noise inside an over-ear headphone cup.
2. **Compressed-audio enhancement:** a low-bitrate MP3 sent over the USB-UART is decoded on the
   ARM and streamed to the PL, which regenerates the treble the encoder removed.

**Plan, schedule and who does what: [docs/plan/](docs/plan/README.md).**

## Layout

| Folder | Contents |
|---|---|
| `rtl/` | PL Verilog |
| `sim/` | Testbenches and test vectors |
| `model/` | Fixed-point Python golden models |
| `sw/` | Vitis bare-metal ARM code |
| `constraints/` | ZedBoard `.xdc` |
| `docs/` | Report, diagrams, measurements |

## Team

| Name | ID |
|---|---|
| Aarav Barnwal | 2023B3A30512H |
| Aadyant Lahiri | 2023B3AA1191H |
| Samarth Shreepad Dixit | 2023B1AA1324H |
| Swarneel Bhattacharjee | 2023AAPS0695H |
