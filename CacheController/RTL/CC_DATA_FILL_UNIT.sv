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

    wire mem_hs = mem_rvalid_i & mem_rready_i;

    wire [17:0] addr_tag    = miss_addr_fifo_rdata_i[31:14];
    wire [7:0]  addr_index  = miss_addr_fifo_rdata_i[13:6];
    wire [5:0]  addr_offset = miss_addr_fifo_rdata_i[5:0];
    wire [2:0]  addr_base   = miss_addr_fifo_rdata_i[5:3];

    logic        active;
    logic [2:0]  beat_cnt;
    logic [2:0]  base_reg;
    logic [17:0] tag_reg;
    logic [7:0]  index_reg;

    logic [63:0] line_words [0:7];

    wire [2:0]  base_use   = active ? base_reg  : addr_base;
    wire [2:0]  cnt_use    = active ? beat_cnt  : 3'd0;
    wire [2:0]  dst_word   = base_use + cnt_use;
    wire [17:0] tag_use    = active ? tag_reg   : addr_tag;
    wire [7:0]  index_use  = active ? index_reg : addr_index;

    wire last_hs   = mem_hs & mem_rlast_i;
    wire have_meta = active | (~active & ~miss_addr_fifo_empty_i);
    wire do_write  = last_hs & have_meta;

    logic [63:0] words_for_out [0:7];
    integer wi;

    always_comb begin
        for (wi=0; wi<8; wi=wi+1) begin
            words_for_out[wi] = line_words[wi];
        end
        if (mem_hs & have_meta) begin
            words_for_out[dst_word] = mem_rdata_i;
        end
    end

    wire [511:0] assembled_line;
    assign assembled_line = { words_for_out[7], words_for_out[6], words_for_out[5], words_for_out[4],
                              words_for_out[3], words_for_out[2], words_for_out[1], words_for_out[0] };

    assign wren_o               = do_write;
    assign miss_addr_fifo_rden_o= do_write;
    assign waddr_o              = index_use;
    assign wdata_tag_o          = {1'b1, tag_use};
    assign wdata_data_o         = assembled_line;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            active    <= 1'b0;
            beat_cnt  <= 3'd0;
            base_reg  <= 3'd0;
            tag_reg   <= '0;
            index_reg <= '0;
            for (int i=0; i<8; i++) begin
                line_words[i] <= 64'd0;
            end
        end else begin
            if (mem_hs) begin
                if (!active) begin
                    if (!miss_addr_fifo_empty_i) begin
                        base_reg  <= addr_base;
                        tag_reg   <= addr_tag;
                        index_reg <= addr_index;

                        line_words[addr_base + 3'd0] <= mem_rdata_i;

                        if (mem_rlast_i) begin
                            active   <= 1'b0;
                            beat_cnt <= 3'd0;
                        end else begin
                            active   <= 1'b1;
                            beat_cnt <= 3'd1;
                        end
                    end
                end else begin
                    line_words[base_reg + beat_cnt] <= mem_rdata_i;

                    if (mem_rlast_i) begin
                        active   <= 1'b0;
                        beat_cnt <= 3'd0;
                    end else begin
                        beat_cnt <= beat_cnt + 3'd1;
                    end
                end
            end
        end
    end

    wire update = do_write;
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
