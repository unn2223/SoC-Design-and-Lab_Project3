// Copyright (c) 2022 Sungkyunkwan University

module CC_DATA_FILL_UNIT
(
    input   wire            clk,
    input   wire            rst_n,
	
    // AMBA AXI interface between MEM and CC (R channel)
    input   wire    [63:0]  mem_rdata_i,
    input   wire            mem_rlast_i,
    input   wire            mem_rvalid_i,
    input   wire            mem_rready_i,

    // Miss Addr FIFO read interface 
    input   wire            miss_addr_fifo_empty_i,
    input   wire    [31:0]  miss_addr_fifo_rdata_i,
    output  wire            miss_addr_fifo_rden_o,

    // SRAM write port interface
    output  wire                wren_o,
    output  wire                wway_o,
    output  wire    [7:0]       waddr_o,
    output  wire    [18:0]      wdata_tag_o,
    output  wire    [511:0]     wdata_data_o
);

    // Fill the code here
    



    //*********************************************************************//
    /* CC_WAY is updated when (update_i signal)
        1. The AXI R channel between MEM and CC performs a handshake 
        2. The last data beat is received.
    Declare update signal, which satisfy upper conditions */
    //*********************************************************************//
    // Pseudo-Random replacement policy
    CC_WAY u_cc_way (
        .clk        (clk),
        .rst_n      (rst_n),
        .update_i   (update),
        .wway_o     (wway_o)
    );
    
endmodule