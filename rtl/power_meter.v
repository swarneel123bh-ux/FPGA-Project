`timescale 1ns / 1ps
// Member C: block mean-square power meter.
// sample_in is signed Q1.23. mean_square_q46 is unsigned Q2.46.
// Default window is 1024 valid samples (WINDOW_LOG2=10).
module power_meter #(
    parameter integer WINDOW_LOG2 = 10
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              clear_window,
    input  wire              sample_valid,
    input  wire signed [23:0] sample_in,
    output reg  [63:0]       mean_square_q46,
    output reg  [23:0]       peak_abs,
    output reg               window_done,
    output reg  [31:0]       total_samples,
    output reg  [31:0]       windows_completed
);
    localparam integer COUNT_W = (WINDOW_LOG2 <= 1) ? 1 : WINDOW_LOG2;
    reg [COUNT_W-1:0] sample_count;
    reg [63:0] sum_squares;
    reg [23:0] peak_running;
    wire signed [47:0] sample_ext = {{24{sample_in[23]}}, sample_in};
    wire signed [47:0] square_signed = sample_ext * sample_ext;
    wire [47:0] square = square_signed[47:0];
    wire [63:0] sum_next = sum_squares + {{16{1'b0}}, square};
    wire [23:0] sample_abs = sample_in[23] ? (~sample_in + 24'd1) : sample_in[23:0];

    always @(posedge clk) begin
        if (rst || clear_window) begin
            sample_count      <= {COUNT_W{1'b0}};
            sum_squares       <= 64'd0;
            peak_running      <= 24'd0;
            mean_square_q46   <= 64'd0;
            peak_abs          <= 24'd0;
            window_done       <= 1'b0;
            total_samples     <= 32'd0;
            windows_completed <= 32'd0;
        end else begin
            window_done <= 1'b0;
            if (sample_valid) begin
                total_samples <= total_samples + 1'b1;
                if (sample_abs > peak_running)
                    peak_running <= sample_abs;

                if (sample_count == ((1 << WINDOW_LOG2) - 1)) begin
                    mean_square_q46 <= sum_next >> WINDOW_LOG2;
                    peak_abs <= (sample_abs > peak_running) ? sample_abs : peak_running;
                    sum_squares <= 64'd0;
                    sample_count <= {COUNT_W{1'b0}};
                    peak_running <= 24'd0;
                    window_done <= 1'b1;
                    windows_completed <= windows_completed + 1'b1;
                end else begin
                    sum_squares <= sum_next;
                    sample_count <= sample_count + 1'b1;
                end
            end
        end
    end
endmodule
