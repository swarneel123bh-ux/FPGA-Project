// -----------------------------------------------------------------------------
// WEEK-1 SCAFFOLDING — review and understand before adopting as team RTL.
// ADAU1761-compatible I2C single-register / burst write engine.
//
// Open-drain bus: the FPGA only pulls SDA/SCL low or releases them (Z).
// Requires external pull-ups. No clock stretching or arbitration support.
// The caller supplies a 7-bit address, 16-bit subaddress, and 1 or 6 data bytes.
// Data is MSB-first: for len=6 use data[47:0]; for len=1 use data[7:0].
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module adau_i2c_write #(
    parameter integer HALF_DIV = 500  // 100 kHz from 100 MHz: 500 clocks/half-bit
)(
    input  wire        clk,
    input  wire        rst,             // synchronous, active high
    input  wire        start,
    input  wire [6:0]  device_addr,
    input  wire [15:0] reg_addr,
    input  wire [2:0]  data_len,        // supported: 1 or 6
    input  wire [47:0] data,
    output reg         busy,
    output reg         done,            // one clk pulse
    output reg         nack,            // sticky until next start
    inout  wire        scl,
    inout  wire        sda
);
    localparam [3:0] ST_IDLE       = 4'd0,
                     ST_START_WAIT = 4'd1,
                     ST_START_HOLD = 4'd2,
                     ST_BIT_LOW    = 4'd3,
                     ST_BIT_HIGH   = 4'd4,
                     ST_ACK_LOW    = 4'd5,
                     ST_ACK_HIGH   = 4'd6,
                     ST_STOP_LOW   = 4'd7,
                     ST_STOP_HIGH  = 4'd8,
                     ST_STOP_END   = 4'd9;

    reg [3:0] state;
    reg [31:0] div_count;
    reg scl_drive_low, sda_drive_low;
    reg [7:0] shift_byte;
    reg [47:0] data_shift;
    reg [15:0] reg_addr_latched;
    reg [2:0] data_len_latched;
    reg [3:0] byte_index;
    reg [3:0] total_bytes;
    reg [2:0] bit_index;
    wire sda_sample = sda;

    assign scl = scl_drive_low ? 1'b0 : 1'bz;
    assign sda = sda_drive_low ? 1'b0 : 1'bz;

    always @(posedge clk) begin
        if (rst) begin
            state            <= ST_IDLE;
            div_count        <= 0;
            scl_drive_low    <= 1'b0;
            sda_drive_low    <= 1'b0;
            shift_byte       <= 8'h00;
            data_shift       <= 48'h0;
            reg_addr_latched<= 16'h0;
            data_len_latched<= 3'd0;
            byte_index       <= 0;
            total_bytes      <= 0;
            bit_index        <= 0;
            busy             <= 1'b0;
            done             <= 1'b0;
            nack             <= 1'b0;
        end else begin
            done <= 1'b0;
            if (state == ST_IDLE) begin
                div_count     <= 0;
                scl_drive_low <= 1'b0;
                sda_drive_low <= 1'b0;
                busy          <= 1'b0;
                if (start) begin
                    if ((data_len == 3'd1) || (data_len == 3'd6)) begin
                        busy              <= 1'b1;
                        nack              <= 1'b0;
                        reg_addr_latched  <= reg_addr;
                        data_len_latched  <= data_len;
                        data_shift        <= (data_len == 3'd6) ? data : {data[7:0], 40'h0};
                        total_bytes       <= 4'd3 + data_len;
                        byte_index        <= 0;
                        bit_index         <= 3'd7;
                        shift_byte        <= {device_addr, 1'b0};
                        state             <= ST_START_WAIT;
                    end else begin
                        nack <= 1'b1;
                        done <= 1'b1;
                    end
                end
            end else if (div_count == HALF_DIV-1) begin
                div_count <= 0;
                case (state)
                    ST_START_WAIT: begin
                        // Bus idle high; create START by pulling SDA low while SCL high.
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b1;
                        state <= ST_START_HOLD;
                    end
                    ST_START_HOLD: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= (shift_byte[7] == 1'b0);
                        state <= ST_BIT_LOW;
                    end
                    ST_BIT_LOW: begin
                        // Data is stable while SCL is low; raise SCL for this bit.
                        scl_drive_low <= 1'b0;
                        state <= ST_BIT_HIGH;
                    end
                    ST_BIT_HIGH: begin
                        scl_drive_low <= 1'b1;
                        if (bit_index != 0) begin
                            bit_index <= bit_index - 1'b1;
                            shift_byte <= {shift_byte[6:0], 1'b0};
                            sda_drive_low <= (shift_byte[6] == 1'b0);
                            state <= ST_BIT_LOW;
                        end else begin
                            sda_drive_low <= 1'b0; // release for subordinate ACK
                            state <= ST_ACK_LOW;
                        end
                    end
                    ST_ACK_LOW: begin
                        scl_drive_low <= 1'b0;
                        state <= ST_ACK_HIGH;
                    end
                    ST_ACK_HIGH: begin
                        // Sample ACK while SCL is high. A high level is NACK.
                        scl_drive_low <= 1'b1;
                        if (sda_sample !== 1'b0) begin
                            nack <= 1'b1;
                            state <= ST_STOP_LOW;
                        end else if (byte_index + 1'b1 >= total_bytes) begin
                            state <= ST_STOP_LOW;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                            bit_index <= 3'd7;
                            if (byte_index == 0)
                                shift_byte <= reg_addr_latched[15:8];
                            else if (byte_index == 1)
                                shift_byte <= reg_addr_latched[7:0];
                            else if (byte_index == 2)
                                shift_byte <= data_shift[47:40];
                            else begin
                                shift_byte <= data_shift[39:32];
                                data_shift <= {data_shift[39:0], 8'h00};
                            end
                            // For all bytes after the first, the next byte's MSB
                            // is already in shift_byte[7] after this assignment.
                            sda_drive_low <= (byte_index == 0) ?
                                             (reg_addr_latched[15] == 1'b0) :
                                             (byte_index == 1) ?
                                             (reg_addr_latched[7] == 1'b0) :
                                             (byte_index == 2) ?
                                             (data_shift[47] == 1'b0) :
                                             (data_shift[39] == 1'b0);
                            state <= ST_BIT_LOW;
                        end
                    end
                    ST_STOP_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b1;
                        state <= ST_STOP_HIGH;
                    end
                    ST_STOP_HIGH: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b1;
                        state <= ST_STOP_END;
                    end
                    ST_STOP_END: begin
                        // STOP: release SDA while SCL is high.
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                    default: begin
                        state <= ST_IDLE;
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        busy <= 1'b0;
                    end
                endcase
            end else begin
                div_count <= div_count + 1'b1;
            end
        end
    end
endmodule
