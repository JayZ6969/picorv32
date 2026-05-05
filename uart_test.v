module uart_test (
    input clk,
    output ser_tx,
    output led1, led2, led3, led4, led5
);
    // 12 MHz clock, 115200 baud -> 104 cycles per bit
    parameter CLK_FREQ = 12000000;
    parameter BAUD = 115200;
    parameter DIV = CLK_FREQ / BAUD;

    reg [31:0] clk_div = 0;
    reg [23:0] blink_div = 0;
    reg [3:0] bit_cnt = 0;
    reg [7:0] data = "H";
    reg [3:0] char_cnt = 0;
    reg tx = 1;

    assign ser_tx = tx;
    assign led1 = blink_div[23];
    assign led2 = ~blink_div[23];
    assign led3 = blink_div[22];
    assign led4 = ~blink_div[22];
    assign led5 = blink_div[21];

    always @(posedge clk) begin
        blink_div <= blink_div + 1;
        
        if (clk_div == DIV - 1) begin
            clk_div <= 0;
            if (bit_cnt == 0) begin
                tx <= 0; // start bit
                bit_cnt <= 1;
            end else if (bit_cnt <= 8) begin
                tx <= data[bit_cnt - 1]; // data bit
                bit_cnt <= bit_cnt + 1;
            end else if (bit_cnt == 9) begin
                tx <= 1; // stop bit
                bit_cnt <= 10;
            end else if (bit_cnt == 10) begin
                // Select next char
                char_cnt <= (char_cnt == 6) ? 0 : char_cnt + 1;
                case (char_cnt)
                    0: data <= "H";
                    1: data <= "e";
                    2: data <= "l";
                    3: data <= "l";
                    4: data <= "o";
                    5: data <= "\r";
                    6: data <= "\n";
                    default: data <= "H";
                endcase
                bit_cnt <= 0;
            end
        end else begin
            clk_div <= clk_div + 1;
        end
    end
endmodule
