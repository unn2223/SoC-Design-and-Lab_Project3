// Copyright (c) 2022 Sungkyunkwan University

module CC_DATA_REORDER_UNIT
(
    input   wire            clk,
    input   wire            rst_n,
	
    // AMBA AXI interface between MEM and CC (R channel)
    input   wire    [63:0]  mem_rdata_i,
    input   wire    [1:0]   mem_rresp_i,
    input   wire            mem_rlast_i,
    input   wire            mem_rvalid_i,
    output  wire            mem_rready_o,    

    // Hit Flag FIFO write interface
    output  wire            hit_flag_fifo_afull_o,
    input   wire            hit_flag_fifo_wren_i,
    input   wire            hit_flag_fifo_wdata_i,

    // Hit data FIFO write interface
    output  wire            hit_data_fifo_afull_o,
    input   wire            hit_data_fifo_wren_i,
    input   wire    [517:0] hit_data_fifo_wdata_i,

	// AMBA AXI interface between INCT and CC (R channel)
    output  wire    [63:0]  inct_rdata_o,
    output  wire    [1:0]   inct_rresp_o,
    output  wire            inct_rlast_o,
    output  wire            inct_rvalid_o,
    input   wire            inct_rready_i
);

    localparam int HIT_FLAG_DEPTH  = 32;
    localparam int HIT_FLAG_AFULL  = HIT_FLAG_DEPTH - 2;

    localparam int HIT_DATA_DEPTH  = 32;
    localparam int HIT_DATA_AFULL  = HIT_DATA_DEPTH - 2;

    localparam int MISS_BEAT_DEPTH = 256;
    localparam int MISS_BEAT_AFULL = MISS_BEAT_DEPTH - 4;

    wire hit_flag_full, hit_flag_empty;
    wire hit_flag_afull, hit_flag_aempty;
    wire hit_flag_rden;
    wire hit_flag_rdata;

    CC_FIFO #(
        .FIFO_DEPTH       (HIT_FLAG_DEPTH),
        .DATA_WIDTH       (1),
        .AFULL_THRESHOLD  (HIT_FLAG_AFULL),
        .AEMPTY_THRESHOLD (0)
    ) u_hit_flag_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .full_o   (hit_flag_full),
        .afull_o  (hit_flag_afull),
        .wren_i   (hit_flag_fifo_wren_i),
        .wdata_i  (hit_flag_fifo_wdata_i),
        .empty_o  (hit_flag_empty),
        .aempty_o (hit_flag_aempty),
        .rden_i   (hit_flag_rden),
        .rdata_o  (hit_flag_rdata)
    );

    wire hit_data_full, hit_data_empty;
    wire hit_data_afull, hit_data_aempty;
    wire hit_data_rden;
    wire [517:0] hit_data_rdata;

    CC_FIFO #(
        .FIFO_DEPTH       (HIT_DATA_DEPTH),
        .DATA_WIDTH       (518),
        .AFULL_THRESHOLD  (HIT_DATA_AFULL),
        .AEMPTY_THRESHOLD (0)
    ) u_hit_data_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .full_o   (hit_data_full),
        .afull_o  (hit_data_afull),
        .wren_i   (hit_data_fifo_wren_i),
        .wdata_i  (hit_data_fifo_wdata_i),
        .empty_o  (hit_data_empty),
        .aempty_o (hit_data_aempty),
        .rden_i   (hit_data_rden),
        .rdata_o  (hit_data_rdata)
    );

    assign hit_flag_fifo_afull_o = hit_flag_afull;
    assign hit_data_fifo_afull_o = hit_data_afull;

    wire miss_full, miss_empty;
    wire miss_afull, miss_aempty;
    wire miss_rden, miss_wren;
    wire [66:0] miss_wdata, miss_rdata;

    assign miss_wdata = {mem_rresp_i, mem_rlast_i, mem_rdata_i};

    CC_FIFO #(
        .FIFO_DEPTH       (MISS_BEAT_DEPTH),
        .DATA_WIDTH       (67),
        .AFULL_THRESHOLD  (MISS_BEAT_AFULL),
        .AEMPTY_THRESHOLD (0)
    ) u_miss_beat_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .full_o   (miss_full),
        .afull_o  (miss_afull),
        .wren_i   (miss_wren),
        .wdata_i  (miss_wdata),
        .empty_o  (miss_empty),
        .aempty_o (miss_aempty),
        .rden_i   (miss_rden),
        .rdata_o  (miss_rdata)
    );

    typedef enum logic [1:0] {ST_IDLE=2'd0, ST_HIT=2'd1, ST_MISS=2'd2} st_t;
    st_t state_q, state_n;

    wire have_token   = ~hit_flag_empty;
    wire head_is_hit  = hit_flag_rdata;
    wire head_is_miss = ~hit_flag_rdata;

    wire start_hit  = (state_q == ST_IDLE) & have_token & head_is_hit  & ~hit_data_empty;
    wire start_miss = (state_q == ST_IDLE) & have_token & head_is_miss;

    wire hit_active  = (state_q == ST_HIT)  | start_hit;
    wire miss_active = (state_q == ST_MISS) | start_miss;

    assign mem_rready_o = rst_n & ~miss_full;
    wire mem_hs = mem_rvalid_i & mem_rready_o;

    logic        skid_valid_q;
    logic [63:0] skid_data_q;
    logic [1:0]  skid_resp_q;
    logic        skid_last_q;

    wire inct_fire;

    wire miss_direct   = miss_active & miss_empty & ~skid_valid_q & mem_rvalid_i;
    wire skid_capture  = miss_direct & mem_hs & ~inct_rready_i;
    wire skid_fire     = miss_active & skid_valid_q & inct_fire;

    assign miss_wren = mem_hs & ~miss_direct;

    wire ser_fifo_empty  = hit_data_empty | ~have_token | ~head_is_hit;
    wire ser_fifo_aempty = hit_data_aempty;

    wire        ser_fifo_rden;
    wire [63:0] ser_rdata;
    wire        ser_rlast;
    wire        ser_rvalid;

    CC_SERIALIZER u_serializer (
        .clk            (clk),
        .rst_n          (rst_n),

        .fifo_empty_i   (ser_fifo_empty),
        .fifo_aempty_i  (ser_fifo_aempty),
        .fifo_rdata_i   (hit_data_rdata),
        .fifo_rden_o    (ser_fifo_rden),

        .rdata_o        (ser_rdata),
        .rlast_o        (ser_rlast),
        .rvalid_o       (ser_rvalid),
        .rready_i       (inct_rready_i & hit_active)
    );

    assign hit_data_rden = ser_fifo_rden;

    wire [1:0]  miss_buf_rresp = miss_rdata[66:65];
    wire        miss_buf_rlast = miss_rdata[64];
    wire [63:0] miss_buf_rdata = miss_rdata[63:0];

    reg  [63:0] rdata_r;
    reg  [1:0]  rresp_r;
    reg         rlast_r;
    reg         rvalid_r;

    always_comb begin
        rdata_r  = 64'd0;
        rresp_r  = 2'b00;
        rlast_r  = 1'b0;
        rvalid_r = 1'b0;

        if (hit_active) begin
            rvalid_r = ser_rvalid;
            rdata_r  = ser_rdata;
            rresp_r  = 2'b00;
            rlast_r  = ser_rlast;

        end else if (miss_active) begin
            if (skid_valid_q) begin
                rvalid_r = 1'b1;
                rdata_r  = skid_data_q;
                rresp_r  = skid_resp_q;
                rlast_r  = skid_last_q;

            end else if (~miss_empty) begin
                rvalid_r = 1'b1;
                rdata_r  = miss_buf_rdata;
                rresp_r  = miss_buf_rresp;
                rlast_r  = miss_buf_rlast;

            end else if (mem_rvalid_i) begin
                rvalid_r = 1'b1;
                rdata_r  = mem_rdata_i;
                rresp_r  = mem_rresp_i;
                rlast_r  = mem_rlast_i;
            end
        end
    end

    assign inct_rdata_o  = rdata_r;
    assign inct_rresp_o  = rresp_r;
    assign inct_rlast_o  = rlast_r;
    assign inct_rvalid_o = rvalid_r;

    assign inct_fire = inct_rvalid_o & inct_rready_i;

    assign miss_rden = miss_active & ~skid_valid_q & ~miss_empty & inct_fire;

    wire burst_done = inct_fire & inct_rlast_o;

    assign hit_flag_rden = burst_done & ~hit_flag_empty;

    always_comb begin
        state_n = state_q;
        unique case (state_q)
            ST_IDLE: begin
                if (start_hit)       state_n = ST_HIT;
                else if (start_miss) state_n = ST_MISS;
            end
            ST_HIT:  if (burst_done) state_n = ST_IDLE;
            ST_MISS: if (burst_done) state_n = ST_IDLE;
            default: state_n = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q      <= ST_IDLE;

            skid_valid_q <= 1'b0;
            skid_data_q  <= 64'd0;
            skid_resp_q  <= 2'b00;
            skid_last_q  <= 1'b0;
        end else begin
            state_q <= state_n;

            if (skid_capture) begin
                skid_valid_q <= 1'b1;
                skid_data_q  <= mem_rdata_i;
                skid_resp_q  <= mem_rresp_i;
                skid_last_q  <= mem_rlast_i;
            end else if (skid_fire) begin
                skid_valid_q <= 1'b0;
            end

            if ((state_q == ST_MISS) && burst_done) begin
                skid_valid_q <= 1'b0;
            end
        end
    end

    // Fill the code here

endmodule