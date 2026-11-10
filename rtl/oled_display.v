`timescale 1ns / 1ps
// Member C reference implementation for the Digilent PmodOLED 128x32 display.
// Assumed display: Digilent PmodOLED (SSD1306 controller, 4-wire SPI).
// It displays two lines:
//   MODE: <CALIBRATE/CANCEL/BYPASS/MUTE/MUSIC>
//   NR: +/-ddd DB
// Mode encoding used here: 0=CALIBRATE, 1=CANCEL, 2=BYPASS, 3=MUTE, 4=MUSIC.
// Change these encodings if Member A's mode_fsm uses different values.
// nr_db is signed whole dB. It is NOT the centi-dB value from anc_measurement.
// Convert attenuation_db_centi to whole dB in the top-level wrapper before connecting.
//
// PmodOLED control pins CS, SDIN, SCLK, D/C, RES, VBATC and VDDC are exposed below.
// VDDC and VBATC are active-low enable controls on the Digilent PmodOLED.
// This module owns the OLED SPI pins; do not connect them to another SPI master.

module oled_display #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer SPI_HZ = 1_000_000
)(
    input  wire              clk,
    input  wire              rst,       // active-high synchronous reset
    input  wire [2:0]        mode,
    input  wire signed [7:0] nr_db,

    output reg               oled_cs_n,
    output reg               oled_sdin,
    output reg               oled_sclk,
    output reg               oled_dc,
    output reg               oled_res_n,
    output reg               oled_vbatc,
    output reg               oled_vddc
);

    localparam integer HALF_DIV_RAW = CLK_HZ / (2 * SPI_HZ);
    localparam integer HALF_DIV = (HALF_DIV_RAW < 1) ? 1 : HALF_DIV_RAW;
    localparam integer VDD_WAIT_CYCLES = CLK_HZ / 1000;   // 1 ms
    localparam integer RESET_CYCLES    = CLK_HZ / 100000; // 10 us
    localparam integer VBAT_WAIT_CYCLES = CLK_HZ / 10;   // 100 ms
    localparam integer INIT_COUNT = 24;

    // High-level sequencer states.
    localparam [5:0]
        ST_VDD_ON          = 6'd0,
        ST_VDD_WAIT        = 6'd1,
        ST_RESET_LOW       = 6'd2,
        ST_RESET_LOW_WAIT  = 6'd3,
        ST_RESET_HIGH      = 6'd4,
        ST_RESET_HIGH_WAIT = 6'd5,
        ST_INIT_SEND       = 6'd6,
        ST_INIT_WAIT_START = 6'd7,
        ST_INIT_WAIT_DONE  = 6'd8,
        ST_CLEAR_CMD_SEND  = 6'd9,
        ST_CLEAR_CMD_START = 6'd10,
        ST_CLEAR_CMD_DONE  = 6'd11,
        ST_CLEAR_DATA_SEND = 6'd12,
        ST_CLEAR_DATA_START= 6'd13,
        ST_CLEAR_DATA_DONE = 6'd14,
        ST_VBAT_ON         = 6'd15,
        ST_VBAT_WAIT       = 6'd16,
        ST_DISPLAY_ON_SEND = 6'd17,
        ST_DISPLAY_ON_START= 6'd18,
        ST_DISPLAY_ON_DONE = 6'd19,
        ST_FRAME_CMD_SEND  = 6'd20,
        ST_FRAME_CMD_START = 6'd21,
        ST_FRAME_CMD_DONE  = 6'd22,
        ST_FRAME_DATA_SEND = 6'd23,
        ST_FRAME_DATA_START= 6'd24,
        ST_FRAME_DATA_DONE = 6'd25,
        ST_RUN              = 6'd26;

    reg [5:0] state;
    reg [31:0] delay_count;
    reg [5:0] init_index;
    reg [2:0] clear_cmd_index;
    reg [2:0] frame_cmd_index;
    reg [9:0] data_index;       // 0..511: four pages x 128 columns
    reg [2:0] frame_mode;
    reg signed [7:0] frame_nr_db;
    reg [2:0] shown_mode;
    reg signed [7:0] shown_nr_db;
    reg shown_valid;

    // Byte-level SPI engine. SPI mode 0: SCLK idles low, MOSI changes while low.
    reg        spi_start;
    reg [7:0]  spi_data;
    reg        spi_dc;
    reg        spi_busy;
    reg [2:0]  spi_bit;
    reg [31:0] spi_div_count;
    reg        spi_second_half;

    function [7:0] init_command;
        input [5:0] index;
        begin
            case (index)
                0:  init_command = 8'hAE; // display off
                1:  init_command = 8'hD5;
                2:  init_command = 8'h80;
                3:  init_command = 8'hA8;
                4:  init_command = 8'h1F; // 32 multiplex rows
                5:  init_command = 8'hD3;
                6:  init_command = 8'h00;
                7:  init_command = 8'h40; // start line 0
                8:  init_command = 8'h8D;
                9:  init_command = 8'h14; // charge pump
                10: init_command = 8'h20;
                11: init_command = 8'h00; // horizontal addressing mode
                12: init_command = 8'hA1; // segment remap
                13: init_command = 8'hC8; // COM scan direction
                14: init_command = 8'hDA;
                15: init_command = 8'h02; // 128x32 COM pin config
                16: init_command = 8'h81;
                17: init_command = 8'h8F; // contrast
                18: init_command = 8'hD9;
                19: init_command = 8'hF1;
                20: init_command = 8'hDB;
                21: init_command = 8'h40;
                22: init_command = 8'hA4; // display follows RAM
                23: init_command = 8'hA6; // normal (not inverted)
                default: init_command = 8'hAE;
            endcase
        end
    endfunction

    function [7:0] clear_command;
        input [2:0] index;
        begin
            case (index)
                0: clear_command = 8'h21; // set column address
                1: clear_command = 8'h00;
                2: clear_command = 8'h7F;
                3: clear_command = 8'h22; // set page address
                4: clear_command = 8'h00;
                5: clear_command = 8'h03;
                default: clear_command = 8'h00;
            endcase
        end
    endfunction

    function [7:0] frame_command;
        input [2:0] index;
        begin
            case (index)
                0: frame_command = 8'h21;
                1: frame_command = 8'h00;
                2: frame_command = 8'h7F;
                3: frame_command = 8'h22;
                4: frame_command = 8'h00;
                5: frame_command = 8'h03;
                default: frame_command = 8'h00;
            endcase
        end
    endfunction

    function [7:0] mode_name_char;
        input [2:0] mode_value;
        input [3:0] position;
        begin
            mode_name_char = 8'h20;
            case (mode_value)
                3'd0: case (position)
                    0: mode_name_char="C"; 1: mode_name_char="A"; 2: mode_name_char="L";
                    3: mode_name_char="I"; 4: mode_name_char="B"; 5: mode_name_char="R";
                    6: mode_name_char="A"; 7: mode_name_char="T"; 8: mode_name_char="E";
                    default: mode_name_char=8'h20;
                endcase
                3'd1: case (position)
                    0: mode_name_char="C"; 1: mode_name_char="A"; 2: mode_name_char="N";
                    3: mode_name_char="C"; 4: mode_name_char="E"; 5: mode_name_char="L";
                    default: mode_name_char=8'h20;
                endcase
                3'd2: case (position)
                    0: mode_name_char="B"; 1: mode_name_char="Y"; 2: mode_name_char="P";
                    3: mode_name_char="A"; 4: mode_name_char="S"; 5: mode_name_char="S";
                    default: mode_name_char=8'h20;
                endcase
                3'd3: case (position)
                    0: mode_name_char="M"; 1: mode_name_char="U"; 2: mode_name_char="T";
                    3: mode_name_char="E"; default: mode_name_char=8'h20;
                endcase
                3'd4: case (position)
                    0: mode_name_char="M"; 1: mode_name_char="U"; 2: mode_name_char="S";
                    3: mode_name_char="I"; 4: mode_name_char="C"; default: mode_name_char=8'h20;
                endcase
                default: case (position)
                    0: mode_name_char="U"; 1: mode_name_char="N"; 2: mode_name_char="K";
                    3: mode_name_char="N"; 4: mode_name_char="O"; 5: mode_name_char="W";
                    6: mode_name_char="N"; default: mode_name_char=8'h20;
                endcase
            endcase
        end
    endfunction

    function [7:0] mode_line_char;
        input [3:0] index;
        input [2:0] mode_value;
        begin
            case (index)
                0: mode_line_char="M";
                1: mode_line_char="O";
                2: mode_line_char="D";
                3: mode_line_char="E";
                4: mode_line_char=":";
                5: mode_line_char=8'h20;
                default: mode_line_char=mode_name_char(mode_value, index - 4'd6);
            endcase
        end
    endfunction

    function [7:0] nr_line_char;
        input [3:0] index;
        input signed [7:0] value;
        integer signed_value;
        integer magnitude;
        integer digit_value;
        begin
            signed_value = value;
            magnitude = (signed_value < 0) ? -signed_value : signed_value;
            case (index)
                0: nr_line_char="N";
                1: nr_line_char="R";
                2: nr_line_char=":";
                3: nr_line_char=8'h20;
                4: nr_line_char=(signed_value < 0) ? "-" : "+";
                5: begin digit_value=(magnitude / 100) % 10; nr_line_char=8'h30+digit_value; end
                6: begin digit_value=(magnitude / 10) % 10; nr_line_char=8'h30+digit_value; end
                7: begin digit_value=magnitude % 10; nr_line_char=8'h30+digit_value; end
                8: nr_line_char=8'h20;
                9: nr_line_char="D";
                10: nr_line_char="B";
                default: nr_line_char=8'h20;
            endcase
        end
    endfunction

    // Five vertical bytes for a compact 5x7 uppercase font. First column is [39:32].
    function [39:0] font5x7;
        input [7:0] ch;
        begin
            case (ch)
                "A": font5x7={8'h7E,8'h11,8'h11,8'h11,8'h7E};
                "B": font5x7={8'h7F,8'h49,8'h49,8'h49,8'h36};
                "C": font5x7={8'h3E,8'h41,8'h41,8'h41,8'h22};
                "D": font5x7={8'h7F,8'h41,8'h41,8'h22,8'h1C};
                "E": font5x7={8'h7F,8'h49,8'h49,8'h49,8'h41};
                "F": font5x7={8'h7F,8'h09,8'h09,8'h09,8'h01};
                "G": font5x7={8'h3E,8'h41,8'h49,8'h49,8'h7A};
                "H": font5x7={8'h7F,8'h08,8'h08,8'h08,8'h7F};
                "I": font5x7={8'h00,8'h41,8'h7F,8'h41,8'h00};
                "J": font5x7={8'h20,8'h40,8'h41,8'h3F,8'h01};
                "K": font5x7={8'h7F,8'h08,8'h14,8'h22,8'h41};
                "L": font5x7={8'h7F,8'h40,8'h40,8'h40,8'h40};
                "M": font5x7={8'h7F,8'h02,8'h0C,8'h02,8'h7F};
                "N": font5x7={8'h7F,8'h04,8'h08,8'h10,8'h7F};
                "O": font5x7={8'h3E,8'h41,8'h41,8'h41,8'h3E};
                "P": font5x7={8'h7F,8'h09,8'h09,8'h09,8'h06};
                "Q": font5x7={8'h3E,8'h41,8'h51,8'h21,8'h5E};
                "R": font5x7={8'h7F,8'h09,8'h19,8'h29,8'h46};
                "S": font5x7={8'h46,8'h49,8'h49,8'h49,8'h31};
                "T": font5x7={8'h01,8'h01,8'h7F,8'h01,8'h01};
                "U": font5x7={8'h3F,8'h40,8'h40,8'h40,8'h3F};
                "V": font5x7={8'h1F,8'h20,8'h40,8'h20,8'h1F};
                "W": font5x7={8'h7F,8'h20,8'h18,8'h20,8'h7F};
                "X": font5x7={8'h63,8'h14,8'h08,8'h14,8'h63};
                "Y": font5x7={8'h03,8'h04,8'h78,8'h04,8'h03};
                "Z": font5x7={8'h61,8'h51,8'h49,8'h45,8'h43};
                "0": font5x7={8'h3E,8'h51,8'h49,8'h45,8'h3E};
                "1": font5x7={8'h00,8'h42,8'h7F,8'h40,8'h00};
                "2": font5x7={8'h62,8'h51,8'h49,8'h49,8'h46};
                "3": font5x7={8'h22,8'h49,8'h49,8'h49,8'h36};
                "4": font5x7={8'h18,8'h14,8'h12,8'h7F,8'h10};
                "5": font5x7={8'h2F,8'h49,8'h49,8'h49,8'h31};
                "6": font5x7={8'h3E,8'h49,8'h49,8'h49,8'h32};
                "7": font5x7={8'h01,8'h71,8'h09,8'h05,8'h03};
                "8": font5x7={8'h36,8'h49,8'h49,8'h49,8'h36};
                "9": font5x7={8'h26,8'h49,8'h49,8'h49,8'h3E};
                ":": font5x7={8'h00,8'h36,8'h36,8'h00,8'h00};
                "+": font5x7={8'h08,8'h08,8'h3E,8'h08,8'h08};
                "-": font5x7={8'h08,8'h08,8'h08,8'h08,8'h08};
                default: font5x7=40'd0;
            endcase
        end
    endfunction

    function [7:0] render_byte;
        input [8:0] address;
        input [2:0] mode_value;
        input signed [7:0] nr_value;
        reg [6:0] column;
        reg [1:0] page;
        reg [3:0] char_index;
        reg [2:0] char_column;
        reg [7:0] character;
        reg [39:0] glyph;
        begin
            page = address[8:7];
            column = address[6:0];
            char_index = column[6:3];
            char_column = column[2:0];
            character = 8'h20;
            if (page == 2'd0)
                character = mode_line_char(char_index, mode_value);
            else if (page == 2'd1)
                character = nr_line_char(char_index, nr_value);
            glyph = font5x7(character);
            if (char_column < 3'd5)
                render_byte = (glyph >> ((4 - char_column) * 8)) & 8'hFF;
            else
                render_byte = 8'h00;
        end
    endfunction

    // SPI transmitter.
    always @(posedge clk) begin
        if (rst) begin
            spi_busy        <= 1'b0;
            spi_bit         <= 3'd7;
            spi_div_count   <= 32'd0;
            spi_second_half <= 1'b0;
            oled_cs_n       <= 1'b1;
            oled_sdin       <= 1'b0;
            oled_sclk       <= 1'b0;
            oled_dc         <= 1'b0;
        end else if (!spi_busy && spi_start) begin
            spi_busy        <= 1'b1;
            spi_bit         <= 3'd7;
            spi_div_count   <= 32'd0;
            spi_second_half <= 1'b0;
            oled_cs_n       <= 1'b0;
            oled_sdin       <= spi_data[7];
            oled_sclk       <= 1'b0;
            oled_dc         <= spi_dc;
        end else if (spi_busy) begin
            if (spi_div_count == HALF_DIV-1) begin
                spi_div_count <= 32'd0;
                if (!spi_second_half) begin
                    oled_sclk       <= 1'b1;
                    spi_second_half <= 1'b1;
                end else begin
                    oled_sclk       <= 1'b0;
                    spi_second_half <= 1'b0;
                    if (spi_bit == 3'd0) begin
                        spi_busy  <= 1'b0;
                        oled_cs_n <= 1'b1;
                    end else begin
                        spi_bit   <= spi_bit - 1'b1;
                        oled_sdin <= spi_data[spi_bit - 1'b1];
                    end
                end
            end else begin
                spi_div_count <= spi_div_count + 1'b1;
            end
        end
    end

    // High-level OLED power-up, clear, and display-update sequencer.
    always @(posedge clk) begin
        if (rst) begin
            state          <= ST_VDD_ON;
            delay_count    <= 32'd0;
            init_index     <= 6'd0;
            clear_cmd_index<= 3'd0;
            frame_cmd_index<= 3'd0;
            data_index     <= 10'd0;
            frame_mode     <= 3'd0;
            frame_nr_db    <= 8'sd0;
            shown_mode     <= 3'd0;
            shown_nr_db    <= 8'sd0;
            shown_valid    <= 1'b0;
            spi_start      <= 1'b0;
            spi_data       <= 8'h00;
            spi_dc         <= 1'b0;
            oled_res_n     <= 1'b1;
            oled_vbatc     <= 1'b1;
            oled_vddc      <= 1'b1;
        end else begin
            spi_start <= 1'b0;
            case (state)
                ST_VDD_ON: begin
                    oled_vddc <= 1'b0; // active-low VDD logic enable
                    delay_count <= 32'd0;
                    state <= ST_VDD_WAIT;
                end
                ST_VDD_WAIT: begin
                    if (delay_count >= VDD_WAIT_CYCLES-1) begin
                        delay_count <= 32'd0;
                        state <= ST_RESET_LOW;
                    end else delay_count <= delay_count + 1'b1;
                end
                ST_RESET_LOW: begin
                    oled_res_n <= 1'b0;
                    delay_count <= 32'd0;
                    state <= ST_RESET_LOW_WAIT;
                end
                ST_RESET_LOW_WAIT: begin
                    if (delay_count >= RESET_CYCLES-1) begin
                        delay_count <= 32'd0;
                        state <= ST_RESET_HIGH;
                    end else delay_count <= delay_count + 1'b1;
                end
                ST_RESET_HIGH: begin
                    oled_res_n <= 1'b1;
                    delay_count <= 32'd0;
                    state <= ST_RESET_HIGH_WAIT;
                end
                ST_RESET_HIGH_WAIT: begin
                    if (delay_count >= RESET_CYCLES-1) begin
                        delay_count <= 32'd0;
                        init_index <= 6'd0;
                        state <= ST_INIT_SEND;
                    end else delay_count <= delay_count + 1'b1;
                end

                ST_INIT_SEND: begin
                    if (!spi_busy) begin
                        spi_data <= init_command(init_index);
                        spi_dc <= 1'b0;
                        spi_start <= 1'b1;
                        state <= ST_INIT_WAIT_START;
                    end
                end
                ST_INIT_WAIT_START: if (spi_busy) state <= ST_INIT_WAIT_DONE;
                ST_INIT_WAIT_DONE: begin
                    if (!spi_busy) begin
                        if (init_index == INIT_COUNT-1) begin
                            clear_cmd_index <= 3'd0;
                            state <= ST_CLEAR_CMD_SEND;
                        end else begin
                            init_index <= init_index + 1'b1;
                            state <= ST_INIT_SEND;
                        end
                    end
                end

                ST_CLEAR_CMD_SEND: begin
                    if (!spi_busy) begin
                        spi_data <= clear_command(clear_cmd_index);
                        spi_dc <= 1'b0;
                        spi_start <= 1'b1;
                        state <= ST_CLEAR_CMD_START;
                    end
                end
                ST_CLEAR_CMD_START: if (spi_busy) state <= ST_CLEAR_CMD_DONE;
                ST_CLEAR_CMD_DONE: begin
                    if (!spi_busy) begin
                        if (clear_cmd_index == 3'd5) begin
                            data_index <= 10'd0;
                            state <= ST_CLEAR_DATA_SEND;
                        end else begin
                            clear_cmd_index <= clear_cmd_index + 1'b1;
                            state <= ST_CLEAR_CMD_SEND;
                        end
                    end
                end

                ST_CLEAR_DATA_SEND: begin
                    if (!spi_busy) begin
                        spi_data <= 8'h00;
                        spi_dc <= 1'b1;
                        spi_start <= 1'b1;
                        state <= ST_CLEAR_DATA_START;
                    end
                end
                ST_CLEAR_DATA_START: if (spi_busy) state <= ST_CLEAR_DATA_DONE;
                ST_CLEAR_DATA_DONE: begin
                    if (!spi_busy) begin
                        if (data_index == 10'd511) begin
                            oled_vbatc <= 1'b0; // active-low OLED panel power enable
                            delay_count <= 32'd0;
                            state <= ST_VBAT_WAIT;
                        end else begin
                            data_index <= data_index + 1'b1;
                            state <= ST_CLEAR_DATA_SEND;
                        end
                    end
                end

                ST_VBAT_WAIT: begin
                    if (delay_count >= VBAT_WAIT_CYCLES-1) begin
                        delay_count <= 32'd0;
                        state <= ST_DISPLAY_ON_SEND;
                    end else delay_count <= delay_count + 1'b1;
                end
                ST_DISPLAY_ON_SEND: begin
                    if (!spi_busy) begin
                        spi_data <= 8'hAF;
                        spi_dc <= 1'b0;
                        spi_start <= 1'b1;
                        state <= ST_DISPLAY_ON_START;
                    end
                end
                ST_DISPLAY_ON_START: if (spi_busy) state <= ST_DISPLAY_ON_DONE;
                ST_DISPLAY_ON_DONE: begin
                    if (!spi_busy) begin
                        frame_mode <= mode;
                        frame_nr_db <= nr_db;
                        frame_cmd_index <= 3'd0;
                        state <= ST_FRAME_CMD_SEND;
                    end
                end

                ST_FRAME_CMD_SEND: begin
                    if (!spi_busy) begin
                        spi_data <= frame_command(frame_cmd_index);
                        spi_dc <= 1'b0;
                        spi_start <= 1'b1;
                        state <= ST_FRAME_CMD_START;
                    end
                end
                ST_FRAME_CMD_START: if (spi_busy) state <= ST_FRAME_CMD_DONE;
                ST_FRAME_CMD_DONE: begin
                    if (!spi_busy) begin
                        if (frame_cmd_index == 3'd5) begin
                            data_index <= 10'd0;
                            state <= ST_FRAME_DATA_SEND;
                        end else begin
                            frame_cmd_index <= frame_cmd_index + 1'b1;
                            state <= ST_FRAME_CMD_SEND;
                        end
                    end
                end

                ST_FRAME_DATA_SEND: begin
                    if (!spi_busy) begin
                        spi_data <= render_byte(data_index[8:0], frame_mode, frame_nr_db);
                        spi_dc <= 1'b1;
                        spi_start <= 1'b1;
                        state <= ST_FRAME_DATA_START;
                    end
                end
                ST_FRAME_DATA_START: if (spi_busy) state <= ST_FRAME_DATA_DONE;
                ST_FRAME_DATA_DONE: begin
                    if (!spi_busy) begin
                        if (data_index == 10'd511) begin
                            shown_mode <= frame_mode;
                            shown_nr_db <= frame_nr_db;
                            shown_valid <= 1'b1;
                            state <= ST_RUN;
                        end else begin
                            data_index <= data_index + 1'b1;
                            state <= ST_FRAME_DATA_SEND;
                        end
                    end
                end

                ST_RUN: begin
                    if (!shown_valid || (mode != shown_mode) || (nr_db != shown_nr_db)) begin
                        frame_mode <= mode;
                        frame_nr_db <= nr_db;
                        frame_cmd_index <= 3'd0;
                        state <= ST_FRAME_CMD_SEND;
                    end
                end

                default: state <= ST_VDD_ON;
            endcase
        end
    end

endmodule
