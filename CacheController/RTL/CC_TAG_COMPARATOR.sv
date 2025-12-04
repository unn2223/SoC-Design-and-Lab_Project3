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

	output	wire			hit_o,
	output	wire			miss_o,

	output 	wire			hs_pulse_delayed_o
);

	// Fill the code here

endmodule
