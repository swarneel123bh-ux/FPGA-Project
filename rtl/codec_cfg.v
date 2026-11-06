// -----------------------------------------------------------------------------
// WEEK-1 SCAFFOLDING — review and understand before adopting as team RTL.
// ADAU1761 power-up/configuration sequencer for the ZedBoard.
//
// Assumptions in this starter configuration:
//   * 100 MHz system clock.
//   * A 24.000 MHz MCLK is forwarded to AC-MCLK (AB2) by mclk_out.v.
//   * ADAU1761 address pins ADDR1=0, ADDR0=0 -> 7-bit I2C address 0x38.
//   * Codec is serial-port MAIN; it drives BCLK and LRCLK to the FPGA.
//   * I2S, stereo, 64 BCLK/frame, 24 significant bits in each 32-bit slot.
//   * LINP and RINP are treated as the two single-ended ADC inputs.
//
// IMPORTANT ANALOG LIMITATION:
// R10/MICBIAS is deliberately left at reset default. ZedBoard JP1 is documented
// as right-channel electret bias only. This RTL cannot make two electret mics
// work until the second-mic bias/wiring decision is made and the register/input
// assumptions are checked against the exact board revision and microphone type.
//
// PLL note: this version waits 10 ms after enabling the PLL, exceeding the
// datasheet's ~2.95 ms typical lock time at 24 MHz, but does NOT poll R1[1].
// Add I2C read/lock polling before treating this as production-ready.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module codec_cfg #(
    parameter integer CLK_HZ          = 100_000_000,
    parameter integer I2C_HZ          = 100_000,
    parameter [6:0]   I2C_ADDR        = 7'h38,
    parameter integer POWERUP_CYCLES  = 1_000_000, // 10 ms @ 100 MHz
    parameter integer PLL_WAIT_CYCLES = 1_000_000, // 10 ms @ 100 MHz
    parameter integer HP_WAIT_CYCLES  = 400_000    // 4 ms @ 100 MHz
)(
    input  wire clk,
    input  wire rst,             // synchronous, active high
    inout  wire codec_scl,
    inout  wire codec_sda,
    output wire busy,
    output reg  ready,
    output reg  error
);
    localparam integer HALF_DIV = CLK_HZ / (2 * I2C_HZ);
    localparam [2:0] C_POWER_WAIT = 3'd0,
                     C_LAUNCH     = 3'd1,
                     C_XFER_WAIT  = 3'd2,
                     C_PLL_WAIT   = 3'd3,
                     C_HP_WAIT    = 3'd4,
                     C_DONE       = 3'd5,
                     C_ERROR      = 3'd6;

    reg [2:0] state;
    reg [31:0] wait_count;
    reg [4:0] rom_index;
    reg i2c_start;
    wire i2c_busy, i2c_done, i2c_nack;
    reg [15:0] rom_addr;
    reg [2:0] rom_len;
    reg [47:0] rom_data;

    assign busy = (state != C_DONE) && (state != C_ERROR);

    // Configuration ROM. Each case is one I2C transaction. The two PLL
    // entries are six-byte burst writes to R1 (0x4002), as required by ADI.
    always @* begin
        rom_addr = 16'h4000;
        rom_len  = 3'd1;
        rom_data = 48'h000000000000;
        case (rom_index)
            5'd0: begin rom_addr=16'h4000; rom_data=48'h000000000000; end // R0 core off/direct
            5'd1: begin rom_addr=16'h4002; rom_len=3'd6; rom_data=48'h000000000000; end // R1 reset/PLL off
            5'd2: begin rom_addr=16'h4002; rom_len=3'd6; rom_data=48'h007D000C2301; end // 24 MHz -> 49.152 MHz
            5'd3: begin rom_addr=16'h4000; rom_data=48'h00000000000F; end // PLL source, 1024fs, core on
            5'd4: begin rom_addr=16'h4015; rom_data=48'h000000000001; end // R15: codec MAIN, stereo, normal polarity
            5'd5: begin rom_addr=16'h4016; rom_data=48'h000000000000; end // R16: I2S, 64 BCLK/frame, 1-bit delay
            5'd6: begin rom_addr=16'h4017; rom_data=48'h000000000000; end // R17: base fs = 48 kHz
            5'd7: begin rom_addr=16'h4009; rom_data=48'h000000000000; end // R3: normal record bias
            5'd8: begin rom_addr=16'h400A; rom_data=48'h000000000051; end // R4: LINP 0 dB, Mixer 1 on
            5'd9: begin rom_addr=16'h400C; rom_data=48'h000000000051; end // R6: RINP 0 dB, Mixer 2 on
            5'd10:begin rom_addr=16'h4019; rom_data=48'h000000000023; end // R19: HPF + both ADCs, analog input
            5'd11:begin rom_addr=16'h401A; rom_data=48'h000000000000; end // R20: left ADC 0 dB
            5'd12:begin rom_addr=16'h401B; rom_data=48'h000000000000; end // R21: right ADC 0 dB
            5'd13:begin rom_addr=16'h4029; rom_data=48'h000000000003; end // R35: left/right playback power
            5'd14:begin rom_addr=16'h402A; rom_data=48'h000000000003; end // R36: both DACs on
            5'd15:begin rom_addr=16'h401C; rom_data=48'h000000000021; end // R22: left DAC -> left playback mixer
            5'd16:begin rom_addr=16'h401E; rom_data=48'h000000000041; end // R24: right DAC -> right playback mixer
            5'd17:begin rom_addr=16'h4023; rom_data=48'h00000000006C; end // R29: left HP muted/disabled, -30 dB
            5'd18:begin rom_addr=16'h4024; rom_data=48'h00000000006D; end // R30: right HP muted, HPMODE on, -30 dB
            5'd19:begin rom_addr=16'h4023; rom_data=48'h00000000006F; end // R29: unmute left HP
            5'd20:begin rom_addr=16'h4024; rom_data=48'h00000000006F; end // R30: unmute right HP
            default: begin rom_addr=16'h4000; rom_len=3'd1; rom_data=48'h0; end
        endcase
    end

    adau_i2c_write #(.HALF_DIV(HALF_DIV)) i2c_writer (
        .clk(clk), .rst(rst), .start(i2c_start),
        .device_addr(I2C_ADDR), .reg_addr(rom_addr),
        .data_len(rom_len), .data(rom_data),
        .busy(i2c_busy), .done(i2c_done), .nack(i2c_nack),
        .scl(codec_scl), .sda(codec_sda)
    );

    always @(posedge clk) begin
        if (rst) begin
            state      <= C_POWER_WAIT;
            wait_count <= 0;
            rom_index  <= 0;
            i2c_start  <= 1'b0;
            ready      <= 1'b0;
            error      <= 1'b0;
        end else begin
            i2c_start <= 1'b0;
            case (state)
                C_POWER_WAIT: begin
                    if (wait_count >= POWERUP_CYCLES-1) begin
                        wait_count <= 0;
                        rom_index <= 0;
                        state <= C_LAUNCH;
                    end else wait_count <= wait_count + 1'b1;
                end
                C_LAUNCH: begin
                    i2c_start <= 1'b1;
                    state <= C_XFER_WAIT;
                end
                C_XFER_WAIT: begin
                    if (i2c_done) begin
                        if (i2c_nack) begin
                            error <= 1'b1;
                            state <= C_ERROR;
                        end else if (rom_index == 5'd2) begin
                            wait_count <= 0;
                            state <= C_PLL_WAIT;
                        end else if (rom_index == 5'd18) begin
                            wait_count <= 0;
                            state <= C_HP_WAIT;
                        end else if (rom_index == 5'd20) begin
                            ready <= 1'b1;
                            state <= C_DONE;
                        end else begin
                            rom_index <= rom_index + 1'b1;
                            state <= C_LAUNCH;
                        end
                    end
                end
                C_PLL_WAIT: begin
                    if (wait_count >= PLL_WAIT_CYCLES-1) begin
                        wait_count <= 0;
                        rom_index <= 5'd3;
                        state <= C_LAUNCH;
                    end else wait_count <= wait_count + 1'b1;
                end
                C_HP_WAIT: begin
                    if (wait_count >= HP_WAIT_CYCLES-1) begin
                        wait_count <= 0;
                        rom_index <= 5'd19;
                        state <= C_LAUNCH;
                    end else wait_count <= wait_count + 1'b1;
                end
                C_DONE: begin ready <= 1'b1; end
                C_ERROR: begin error <= 1'b1; end
                default: begin state <= C_ERROR; error <= 1'b1; end
            endcase
        end
    end
endmodule
