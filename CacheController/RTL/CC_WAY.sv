// Copyright (c) 2022 Sungkyunkwan University

module CC_WAY
(
    input   wire    clk,
    input   wire    rst_n,

    input   wire    update_i,

    output  wire    wway_o
);

    reg [7:0]   lfsr;
    reg         wway;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            lfsr   <= 8'h1;
            wway <= 1'b0;
        end else if (update_i) begin
            wway <= lfsr[0];

            // 8-bit LFSR (x^8 + x^6 + x^5 + x^4 + 1)
            lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
        end
    end

    assign wway_o = wway;
endmodule
