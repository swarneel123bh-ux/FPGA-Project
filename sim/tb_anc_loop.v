`timescale 1ns / 1ps
// Standalone Week-1 closed-loop RTL test for Member B.
//
// This test instantiates the real fxlms RTL, a 1-cycle synchronous shat RAM,
// and fixed-point synthetic P/S FIR paths. It compares the resulting e and y
// against the Python fixed-point vectors. Once Member C's sec_path_id port list
// is available, replace the local shat RAM below with C's module; the plant
// and comparisons can remain unchanged.

module tb_anc_loop;
    localparam integer L = 64;
    localparam integer M = 128;
    localparam integer NUM = 4096;
    localparam integer WAIT_CYCLES = 2000; // [Claude pipelining 11 Nov] was 420; pipelined fxlms needs ~1290 clocks, a 48 kHz sample is ~2083

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg sample_tick = 1'b0;
    reg anc_en = 1'b1;
    reg w_reset = 1'b0;
    reg signed [23:0] x_ref = 24'sd0;
    reg signed [23:0] e_err = 24'sd0;
    wire signed [23:0] y_anti;
    wire [6:0] shat_addr;
    reg signed [23:0] shat_data = 24'sd0;
    wire w_over;

    reg signed [23:0] x_mem [0:NUM-1];
    reg signed [23:0] e_expected [0:NUM-1];
    reg signed [23:0] y_expected [0:NUM-1];
    reg w_expected [0:NUM-1];
    reg signed [23:0] shat_mem [0:M-1];

    // One-cycle synchronous coefficient RAM, as specified in README §5.
    always @(posedge clk)
        shat_data <= shat_mem[shat_addr];

    fxlms #(.L(L), .M(M), .MU_SHIFT(7)) dut (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .anc_en(anc_en), .w_reset(w_reset), .x_ref(x_ref), .e_err(e_err),
        .y_anti(y_anti), .shat_addr(shat_addr), .shat_data(shat_data),
        .w_over(w_over)
    );

    // Synthetic path coefficients in signed Q2.22.
    // P[6]=0.80, P[7]=0.15; S[2]=0.70, S[3]=0.20.
    reg signed [23:0] p_q [0:7];
    reg signed [23:0] s_q [0:3];
    reg signed [23:0] x_history [0:7];
    reg signed [23:0] y_history [0:2];

    reg signed [63:0] primary_acc;
    reg signed [63:0] secondary_acc;
    reg signed [47:0] path_product;
    reg signed [23:0] disturbance;
    reg signed [23:0] secondary_output;
    reg signed [23:0] e_calculated;
    integer i;
    integer k;
    integer errors;
    integer csv_fd;

    function signed [63:0] round_shift64_tb;
        input signed [63:0] value;
        input integer shift;
        reg signed [63:0] magnitude;
        reg signed [63:0] rounded_magnitude;
        begin
            if (shift <= 0)
                round_shift64_tb = value <<< (-shift);
            else if (value >= 0)
                round_shift64_tb = (value + (64'sd1 <<< (shift-1))) >>> shift;
            else begin
                magnitude = -value;
                rounded_magnitude = (magnitude + (64'sd1 <<< (shift-1))) >>> shift;
                round_shift64_tb = -rounded_magnitude;
            end
        end
    endfunction

    function signed [23:0] sat24_tb;
        input signed [63:0] value;
        begin
            if (value > 64'sd8388607)
                sat24_tb = 24'sh7fffff;
            else if (value < -64'sd8388608)
                sat24_tb = 24'sh800000;
            else
                sat24_tb = value[23:0];
        end
    endfunction

    initial begin
        errors = 0;
        $readmemh("sim/vectors/fxlms_xref.hex", x_mem);
        $readmemh("sim/vectors/fxlms_eerr.hex", e_expected);
        $readmemh("sim/vectors/fxlms_yanti.hex", y_expected);
        $readmemh("sim/vectors/fxlms_w_over.hex", w_expected);
        $readmemh("sim/vectors/fxlms_shat.hex", shat_mem);

        for (i = 0; i < 8; i = i + 1) begin
            p_q[i] = 24'sd0;
            x_history[i] = 24'sd0;
        end
        for (i = 0; i < 4; i = i + 1)
            s_q[i] = 24'sd0;
        for (i = 0; i < 3; i = i + 1)
            y_history[i] = 24'sd0;
        p_q[6] = 24'sh333333;
        p_q[7] = 24'sh09999a;
        s_q[2] = 24'sh2ccccd;
        s_q[3] = 24'sh0ccccd;

        csv_fd = $fopen("sim/vectors/rtl_anc_loop.csv", "w");
        if (csv_fd == 0) $fatal(1, "Could not open rtl_anc_loop.csv");
        $fdisplay(csv_fd, "sample,disturbance,error,y_anti");

        repeat (4) @(negedge clk);
        rst = 1'b0;
        w_reset = 1'b1;
        repeat (2) @(negedge clk);
        w_reset = 1'b0;

        for (i = 0; i < NUM; i = i + 1) begin
            @(negedge clk);
            x_ref = x_mem[i];

            // Primary path: current x history includes x[n].
            for (k = 7; k > 0; k = k - 1)
                x_history[k] = x_history[k-1];
            x_history[0] = x_ref;
            primary_acc = 64'sd0;
            for (k = 0; k < 8; k = k + 1) begin
                path_product = $signed({{24{p_q[k][23]}}, p_q[k]}) * $signed({{24{x_history[k][23]}}, x_history[k]});
                primary_acc = primary_acc + {{16{path_product[47]}}, path_product};
            end
            disturbance = sat24_tb(round_shift64_tb(primary_acc, 22));

            // Secondary path includes the output-sample pipeline delay.
            // At this tick the newest completed controller output is y[n-1],
            // so S[1] multiplies history[0], S[2] multiplies history[1], etc.
            secondary_acc = 64'sd0;
            for (k = 1; k < 4; k = k + 1) begin
                path_product = $signed({{24{s_q[k][23]}}, s_q[k]}) * $signed({{24{y_history[k-1][23]}}, y_history[k-1]});
                secondary_acc = secondary_acc + {{16{path_product[47]}}, path_product};
            end
            secondary_output = sat24_tb(round_shift64_tb(secondary_acc, 22));
            e_calculated = sat24_tb($signed(disturbance) + $signed(secondary_output));
            e_err = e_calculated;

            if (e_calculated !== e_expected[i]) begin
                $display("PLANT ERROR mismatch sample=%0d got=%0d expected=%0d", i, e_calculated, e_expected[i]);
                errors = errors + 1;
                if (errors >= 10) $fatal(1, "Too many plant mismatches");
            end

            sample_tick = 1'b1;
            @(negedge clk);
            sample_tick = 1'b0;
            repeat (WAIT_CYCLES) @(negedge clk);

            if (y_anti !== y_expected[i]) begin
                $display("RTL ERROR mismatch sample=%0d y_got=%0d expected=%0d", i, y_anti, y_expected[i]);
                errors = errors + 1;
                if (errors >= 10) $fatal(1, "Too many RTL mismatches");
            end
            if (w_over !== w_expected[i]) begin
                $display("w_over mismatch sample=%0d got=%b expected=%b", i, w_over, w_expected[i]);
                errors = errors + 1;
                if (errors >= 10) $fatal(1, "Too many w_over mismatches");
            end

            $fdisplay(csv_fd, "%0d,%0d,%0d,%0d", i, disturbance, e_calculated, y_anti);
            for (k = 2; k > 0; k = k - 1)
                y_history[k] = y_history[k-1];
            y_history[0] = y_anti;
        end

        $fclose(csv_fd);
        if (errors == 0)
            $display("PASS: closed-loop RTL, P/S paths and ideal shat match Python for %0d samples", NUM);
        else
            $fatal(1, "FAIL: %0d closed-loop mismatches", errors);
        $finish;
    end
endmodule
