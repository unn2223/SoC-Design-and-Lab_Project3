// Copyright (c) 2022 Sungkyunkwan University

module CC_TAG_COMPARATOR
(
	input	wire			clk,
	input	wire			rst_n,

	input	wire	[17:0]	tag_i,
	input	wire	[7:0]	index_i,
	input   wire	[5:0]	offset_i,
	output	wire	[17:0]	tag_delayed_o,
	output	wire	[7:0]	index_delayed_o,
	output	wire	[5:0]	offset_delayed_o,

	input	wire			hs_pulse_i,
	input   wire    [18:0]  rdata_tag_i,
	output	wire			hit_o,
	output	wire			miss_o,

	output 	wire			hs_pulse_delayed_o
);

	logic [17:0] tag_d;
    logic [7:0]  index_d;
    logic [5:0]  offset_d;
    logic        hs_d;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tag_d    <= '0;
            index_d  <= '0;
            offset_d <= '0;
            hs_d     <= 1'b0;
        end else begin
            hs_d <= hs_pulse_i;
            if (hs_pulse_i) begin
                tag_d    <= tag_i;
                index_d  <= index_i;
                offset_d <= offset_i;
            end
        end
    end

    assign tag_delayed_o      = tag_d;
    assign index_delayed_o    = index_d;
    assign offset_delayed_o   = offset_d;
    assign hs_pulse_delayed_o = hs_d;

    wire        stored_valid = rdata_tag_i[18];
    wire [17:0] stored_tag   = rdata_tag_i[17:0];

    wire hit_int;
    assign hit_int = hs_d & stored_valid & (stored_tag == tag_d);

    assign hit_o  = hit_int;
    assign miss_o = hs_d & ~hit_int;
	// Fill the code here

endmodule
