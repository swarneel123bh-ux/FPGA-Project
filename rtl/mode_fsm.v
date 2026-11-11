`timescale 1ns/1ps
// Member A: five-mode control FSM. All controls are synchronous to clk.
// mode_sel: 00=ANC, 01=BYPASS, 10=MUSIC, 11=reserved (ANC).
module mode_fsm #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer CALIBRATION_SECONDS = 5,
    parameter integer CAL_CYCLES = CLK_HZ * CALIBRATION_SECONDS
)(
    input wire clk, input wire rst,
    input wire [1:0] mode_sel,
    input wire recalibrate,
    input wire cal_done,       // optional external completion; timer also completes
    input wire diverge,
    input wire fifo_underrun,
    output reg [2:0] mode,
    output wire cal_en,
    output wire anc_en,
    output wire w_reset,
    output reg cal_done_pulse
);
    localparam [2:0] CALIBRATE=3'd0, CANCEL=3'd1, BYPASS=3'd2, MUTE=3'd3, MUSIC=3'd4;
    localparam integer CW = (CAL_CYCLES < 2) ? 1 : $clog2(CAL_CYCLES+1);
    reg [CW-1:0] cal_count;
    reg mute_seen;

    assign cal_en = (mode == CALIBRATE);
    assign anc_en = (mode == CANCEL) && (mode_sel == 2'b00);
    assign w_reset = (mode == MUTE);

    always @(posedge clk) begin
      if (rst) begin
        mode <= CALIBRATE;
        cal_count <= {CW{1'b0}};
        cal_done_pulse <= 1'b0;
        mute_seen <= 1'b0;
      end else begin
        cal_done_pulse <= 1'b0;
        case (mode)
          CALIBRATE: begin
            if (mode_sel == 2'b01) mode <= BYPASS;
            else if (mode_sel == 2'b10) mode <= MUSIC;
            else if (cal_done || (cal_count >= CAL_CYCLES-1)) begin
              mode <= CANCEL; cal_count <= {CW{1'b0}}; cal_done_pulse <= 1'b1;
            end else cal_count <= cal_count + 1'b1;
          end
          CANCEL: begin
            if (recalibrate) begin mode <= CALIBRATE; cal_count <= 0; end
            else if (mode_sel == 2'b01) mode <= BYPASS;
            else if (mode_sel == 2'b10) mode <= MUSIC;
            else if (diverge) mode <= MUTE;
          end
          BYPASS: begin
            if (recalibrate) begin mode <= CALIBRATE; cal_count <= 0; end
            else if (mode_sel == 2'b00) begin mode <= CALIBRATE; cal_count <= 0; end
            else if (mode_sel == 2'b10) mode <= MUSIC;
          end
          MUTE: begin
            // Keep w_reset asserted for one full clock, then restart calibration.
            if (!mute_seen) mute_seen <= 1'b1;
            else begin mode <= CALIBRATE; cal_count <= 0; mute_seen <= 1'b0; end
          end
          MUSIC: begin
            if (fifo_underrun) mode <= BYPASS;
            else if (recalibrate) begin mode <= CALIBRATE; cal_count <= 0; end
            else if (mode_sel == 2'b00) begin mode <= CALIBRATE; cal_count <= 0; end
            else if (mode_sel == 2'b01) mode <= BYPASS;
          end
          default: begin mode <= CALIBRATE; cal_count <= 0; end
        endcase
      end
    end
endmodule
