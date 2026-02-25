module CC_TOP
(
    input   wire        clk,
    input   wire        rst_n,

    // AMBA APB interface
    input   wire                psel_i,
    input   wire                penable_i,
    input   wire    [11:0]      paddr_i,
    input   wire                pwrite_i,
    input   wire    [31:0]      pwdata_i,
    output  reg                 pready_o,
    output  reg     [31:0]      prdata_o,
    output  reg                 pslverr_o,

    // AMBA AXI interface between INCT and CC (AR channel)
    input   wire    [3:0]       inct_arid_i,
    input   wire    [31:0]      inct_araddr_i,
    input   wire    [3:0]       inct_arlen_i,
    input   wire    [2:0]       inct_arsize_i,
    input   wire    [1:0]       inct_arburst_i,
    input   wire                inct_arvalid_i,
    output  wire                inct_arready_o,
    
    // AMBA AXI interface between INCT and CC  (R channel)
    output  wire    [3:0]       inct_rid_o,
    output  wire    [63:0]      inct_rdata_o,
    output  wire    [1:0]       inct_rresp_o,
    output  wire                inct_rlast_o,
    output  wire                inct_rvalid_o,
    input   wire                inct_rready_i,

    // AMBA AXI interface between memory and CC (AR channel)
    output  wire    [3:0]       mem_arid_o,
    output  wire    [31:0]      mem_araddr_o,
    output  wire    [3:0]       mem_arlen_o,
    output  wire    [2:0]       mem_arsize_o,
    output  wire    [1:0]       mem_arburst_o,
    output  wire                mem_arvalid_o,
    input   wire                mem_arready_i,

    // AMBA AXI interface between memory and CC  (R channel)
    input   wire    [3:0]       mem_rid_i,
    input   wire    [63:0]      mem_rdata_i,
    input   wire    [1:0]       mem_rresp_i,
    input   wire                mem_rlast_i,
    input   wire                mem_rvalid_i,
    output  wire                mem_rready_o,    

    // SRAM read port interface
    output  wire                rden_o,
    output  wire    [7:0]       raddr_o,
    input   wire    [18:0]      rdata_tag0_i,
    input   wire    [18:0]      rdata_tag1_i,
    input   wire    [511:0]     rdata_data0_i,
    input   wire    [511:0]     rdata_data1_i,

    // SRAM write port interface
    output  wire                wren_o,
    output  wire    [7:0]       waddr_o,
    output  wire                wway_o,
    output  wire    [18:0]      wdata_tag_o,
    output  wire    [511:0]     wdata_data_o    
);

    // You can modify the code in the module block.
    
    CC_CFG u_cfg(
        .clk            (clk),
        .rst_n          (rst_n),
        .psel_i         (psel_i),
        .penable_i      (penable_i),
        .paddr_i        (paddr_i),
        .pwrite_i       (pwrite_i),
        .pwdata_i       (pwdata_i),
        .pready_o       (pready_o),
        .prdata_o       (prdata_o),
        .pslverr_o      (pslverr_o)
    );
    
    localparam int MISS_REQ_DEPTH  = 8;
    localparam int MISS_REQ_AFULL  = 6;

    localparam int MISS_ADDR_DEPTH = 8;
    localparam int MISS_ADDR_AFULL = 6;

    localparam int ID_DEPTH        = 16;
    localparam int ID_AFULL        = 14;

    wire spec_ok;
    assign spec_ok = rst_n &
                     (inct_arlen_i   == 4'd7) &
                     (inct_arsize_i  == 3'b011) &
                     (inct_arburst_i == 2'b10) &
                     (inct_araddr_i[2:0] == 3'b000);

    wire reorder_hit_flag_afull;
    wire reorder_hit_data_afull;

    wire hit_flag_fifo_wren;
    wire hit_flag_fifo_wdata;

    wire hit_data_fifo_wren;
    wire [517:0] hit_data_fifo_wdata;

    wire [63:0] reorder_rdata;
    wire [1:0]  reorder_rresp;
    wire        reorder_rlast;
    wire        reorder_rvalid;

    CC_DATA_REORDER_UNIT u_reorder (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .mem_rdata_i            (mem_rdata_i),
        .mem_rresp_i            (mem_rresp_i),
        .mem_rlast_i            (mem_rlast_i),
        .mem_rvalid_i           (mem_rvalid_i),
        .mem_rready_o           (mem_rready_o),

        .hit_flag_fifo_afull_o  (reorder_hit_flag_afull),
        .hit_flag_fifo_wren_i   (hit_flag_fifo_wren),
        .hit_flag_fifo_wdata_i  (hit_flag_fifo_wdata),

        .hit_data_fifo_afull_o  (reorder_hit_data_afull),
        .hit_data_fifo_wren_i   (hit_data_fifo_wren),
        .hit_data_fifo_wdata_i  (hit_data_fifo_wdata),

        .inct_rdata_o           (reorder_rdata),
        .inct_rresp_o           (reorder_rresp),
        .inct_rlast_o           (reorder_rlast),
        .inct_rvalid_o          (reorder_rvalid),
        .inct_rready_i          (inct_rready_i)
    );

    assign inct_rdata_o  = reorder_rdata;
    assign inct_rresp_o  = reorder_rresp;
    assign inct_rlast_o  = reorder_rlast;
    assign inct_rvalid_o = reorder_rvalid;

    wire r_done = reorder_rvalid & inct_rready_i & reorder_rlast;

    wire miss_req_full, miss_req_afull, miss_req_empty, miss_req_aempty;
    wire [31:0] miss_req_rdata;
    wire miss_req_wren, miss_req_rden;
    wire [31:0] miss_req_wdata;

    wire miss_addr_full, miss_addr_afull, miss_addr_empty, miss_addr_aempty;
    wire [31:0] miss_addr_rdata;
    wire miss_addr_wren_to_fifo, miss_addr_rden;
    wire [31:0] miss_addr_wdata;

    wire id_full, id_afull, id_empty, id_aempty;
    wire [3:0] id_rdata;
    wire id_wren, id_rden;
    wire [3:0] id_wdata;

    CC_FIFO #(
        .FIFO_DEPTH       (MISS_REQ_DEPTH),
        .DATA_WIDTH       (32),
        .AFULL_THRESHOLD  (MISS_REQ_AFULL),
        .AEMPTY_THRESHOLD (0)
    ) u_miss_req_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .full_o   (miss_req_full),
        .afull_o  (miss_req_afull),
        .wren_i   (miss_req_wren),
        .wdata_i  (miss_req_wdata),
        .empty_o  (miss_req_empty),
        .aempty_o (miss_req_aempty),
        .rden_i   (miss_req_rden),
        .rdata_o  (miss_req_rdata)
    );

    CC_FIFO #(
        .FIFO_DEPTH       (MISS_ADDR_DEPTH),
        .DATA_WIDTH       (32),
        .AFULL_THRESHOLD  (MISS_ADDR_AFULL),
        .AEMPTY_THRESHOLD (0)
    ) u_miss_addr_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .full_o   (miss_addr_full),
        .afull_o  (miss_addr_afull),
        .wren_i   (miss_addr_wren_to_fifo),
        .wdata_i  (miss_addr_wdata),
        .empty_o  (miss_addr_empty),
        .aempty_o (miss_addr_aempty),
        .rden_i   (miss_addr_rden),
        .rdata_o  (miss_addr_rdata)
    );

    CC_FIFO #(
        .FIFO_DEPTH       (ID_DEPTH),
        .DATA_WIDTH       (4),
        .AFULL_THRESHOLD  (ID_AFULL),
        .AEMPTY_THRESHOLD (0)
    ) u_id_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .full_o   (id_full),
        .afull_o  (id_afull),
        .wren_i   (id_wren),
        .wdata_i  (id_wdata),
        .empty_o  (id_empty),
        .aempty_o (id_aempty),
        .rden_i   (id_rden),
        .rdata_o  (id_rdata)
    );

    assign inct_rid_o = id_empty ? 4'd0 : id_rdata;
    assign id_rden    = r_done & ~id_empty;

    localparam int MISSQ_W = $clog2(MISS_REQ_DEPTH+1);
    reg [25:0] missq_line [0:MISS_REQ_DEPTH-1];
    reg [MISSQ_W-1:0] missq_count;

    // pipe_inflight-based guard removed:
    // Use only FIFO's raw afull/full for backpressure into decoder.
    wire miss_req_afull_for_dec  = miss_req_afull  | miss_req_full;
    wire miss_addr_afull_for_dec = miss_addr_afull | miss_addr_full;

    wire [17:0] dec_tag;
    wire [7:0]  dec_index;
    wire [5:0]  dec_offset;
    wire        dec_hs_pulse;
    wire        dec_arready;

    wire inct_arvalid_gated;

    wire hit_flag_afull_for_dec = reorder_hit_flag_afull | id_afull | id_full;

    CC_DECODER u_decoder (
        .inct_araddr_i           (inct_araddr_i),
        .inct_arvalid_i          (inct_arvalid_gated),
        .inct_arready_o          (dec_arready),

        .miss_addr_fifo_afull_i  (miss_addr_afull_for_dec),
        .miss_req_fifo_afull_i   (miss_req_afull_for_dec),
        .hit_flag_fifo_afull_i   (hit_flag_afull_for_dec),
        .hit_data_fifo_afull_i   (reorder_hit_data_afull),

        .tag_o                   (dec_tag),
        .index_o                 (dec_index),
        .offset_o                (dec_offset),
        .hs_pulse_o              (dec_hs_pulse)
    );

    assign rden_o  = dec_hs_pulse;
    assign raddr_o = dec_index;

    wire ar_hs = inct_arvalid_i & inct_arready_o;

    assign id_wren  = ar_hs;
    assign id_wdata = inct_arid_i;

    wire [17:0] tag_d0, tag_d1;
    wire [7:0]  index_d0, index_d1;
    wire [5:0]  offset_d0, offset_d1;
    wire        hs_d0, hs_d1;
    wire        hit0, hit1;

    CC_TAG_COMPARATOR u_cmp0 (
        .clk                (clk),
        .rst_n              (rst_n),
        .tag_i              (dec_tag),
        .index_i            (dec_index),
        .offset_i           (dec_offset),
        .tag_delayed_o      (tag_d0),
        .index_delayed_o    (index_d0),
        .offset_delayed_o   (offset_d0),
        .hs_pulse_i         (dec_hs_pulse),
        .rdata_tag_i        (rdata_tag0_i),
        .hit_o              (hit0),
        .miss_o             (),
        .hs_pulse_delayed_o (hs_d0)
    );

    CC_TAG_COMPARATOR u_cmp1 (
        .clk                (clk),
        .rst_n              (rst_n),
        .tag_i              (dec_tag),
        .index_i            (dec_index),
        .offset_i           (dec_offset),
        .tag_delayed_o      (tag_d1),
        .index_delayed_o    (index_d1),
        .offset_delayed_o   (offset_d1),
        .hs_pulse_i         (dec_hs_pulse),
        .rdata_tag_i        (rdata_tag1_i),
        .hit_o              (hit1),
        .miss_o             (),
        .hs_pulse_delayed_o (hs_d1)
    );

    wire [17:0] tag_delayed      = tag_d0;
    wire [7:0]  index_delayed    = index_d0;
    wire [5:0]  offset_delayed   = offset_d0;
    wire        hs_pulse_delayed = hs_d0;

    wire is_hit  = hit0 | hit1;
    wire hit_way = hit1 ? 1'b1 : 1'b0;

    wire [511:0] hit_line_data = hit_way ? rdata_data1_i : rdata_data0_i;


    wire [31:0] miss_addr32 = {tag_delayed, index_delayed, offset_delayed};

    wire        new_miss_valid = hs_pulse_delayed & ~is_hit;
    wire [31:0] new_miss_addr  = miss_addr32;
    wire [25:0] new_miss_line  = new_miss_addr[31:6];

    reg mem_outstanding;
    wire mem_r_last_fire       = mem_rvalid_i & mem_rready_o & mem_rlast_i;
    wire mem_outstanding_eff   = mem_outstanding & ~mem_r_last_fire;

    reg        direct_hold_valid;
    reg [31:0] direct_hold_addr;

    wire sel_hold = direct_hold_valid;
    wire sel_fifo = (~direct_hold_valid) & (~miss_req_empty);
    wire sel_new  = (~direct_hold_valid) & miss_req_empty & new_miss_valid;

    wire [31:0] issue_addr =
        sel_hold ? direct_hold_addr :
        (sel_fifo ? miss_req_rdata : new_miss_addr);

    wire have_issue = direct_hold_valid | (~miss_req_empty) | new_miss_valid;

    assign mem_arvalid_o = (~mem_outstanding_eff) & have_issue;
    assign mem_araddr_o  = mem_arvalid_o ? issue_addr : 32'd0;

    assign mem_arlen_o   = 4'd7;
    assign mem_arsize_o  = 3'b011;
    assign mem_arburst_o = 2'b10;
    assign mem_arid_o    = 4'd0;

    wire mem_ar_fire = mem_arvalid_o & mem_arready_i;

    assign miss_req_rden = mem_ar_fire & sel_fifo;

    wire direct_issue_fire = mem_ar_fire & sel_new;

    wire hold_set = (~mem_outstanding_eff) & sel_new & ~mem_arready_i;
    wire hold_clr = mem_ar_fire & direct_hold_valid;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            direct_hold_valid <= 1'b0;
            direct_hold_addr  <= 32'd0;
        end else begin
            if (hold_set) begin
                direct_hold_valid <= 1'b1;
                direct_hold_addr  <= new_miss_addr;
            end else if (hold_clr) begin
                direct_hold_valid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_outstanding <= 1'b0;
        end else begin
            case ({mem_ar_fire, mem_r_last_fire})
                2'b10: mem_outstanding <= 1'b1;
                2'b01: mem_outstanding <= 1'b0;
                2'b11: mem_outstanding <= 1'b1;
                default: mem_outstanding <= mem_outstanding;
            endcase
        end
    end

    reg        pend_valid;
    reg [25:0] pend_line;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pend_valid <= 1'b0;
            pend_line  <= 26'd0;
        end else begin
            case ({mem_ar_fire, mem_r_last_fire})
                2'b10: begin
                    pend_valid <= 1'b1;
                    pend_line  <= issue_addr[31:6];
                end
                2'b01: begin
                    pend_valid <= 1'b0;
                end
                2'b11: begin
                    pend_valid <= 1'b1;
                    pend_line  <= issue_addr[31:6];
                end
                default: begin
                    pend_valid <= pend_valid;
                    pend_line  <= pend_line;
                end
            endcase
        end
    end

    wire pend_valid_eff = pend_valid & ~mem_r_last_fire;
    wire pend_match     = pend_valid_eff & (inct_araddr_i[31:6] == pend_line);

    wire hold_match     = direct_hold_valid & (inct_araddr_i[31:6] == direct_hold_addr[31:6]);

    wire missq_push = miss_req_wren & ~miss_req_full;
    wire missq_pop  = miss_req_rden & ~miss_req_empty;

    integer qi;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            missq_count <= '0;
            for (qi=0; qi<MISS_REQ_DEPTH; qi=qi+1) begin
                missq_line[qi] <= 26'd0;
            end
        end else begin
            if (missq_push & ~missq_pop) begin
                if (missq_count < MISS_REQ_DEPTH[MISSQ_W-1:0]) begin
                    missq_line[missq_count] <= miss_req_wdata[31:6];
                    missq_count <= missq_count + {{(MISSQ_W-1){1'b0}},1'b1};
                end
            end else if (~missq_push & missq_pop) begin
                for (qi=0; qi<MISS_REQ_DEPTH-1; qi=qi+1) begin
                    missq_line[qi] <= missq_line[qi+1];
                end
                missq_line[MISS_REQ_DEPTH-1] <= 26'd0;
                if (missq_count != '0) begin
                    missq_count <= missq_count - {{(MISSQ_W-1){1'b0}},1'b1};
                end
            end else if (missq_push & missq_pop) begin
                for (qi=0; qi<MISS_REQ_DEPTH-1; qi=qi+1) begin
                    missq_line[qi] <= missq_line[qi+1];
                end
                if (missq_count != '0) begin
                    missq_line[missq_count-1] <= miss_req_wdata[31:6];
                end else begin
                    missq_line[0] <= miss_req_wdata[31:6];
                end
                missq_count <= missq_count;
            end
        end
    end

    reg missq_any_match;
    integer qj;
    always_comb begin
        missq_any_match = 1'b0;
        for (qj=0; qj<MISS_REQ_DEPTH; qj=qj+1) begin
            if (qj < missq_count) begin
                missq_any_match = missq_any_match | (inct_araddr_i[31:6] == missq_line[qj]);
            end
        end
    end

    wire newmiss_match = new_miss_valid & (inct_araddr_i[31:6] == new_miss_line);

    wire dup_match = pend_match | hold_match | missq_any_match | newmiss_match;

    assign inct_arvalid_gated = inct_arvalid_i & spec_ok & ~dup_match;
    assign inct_arready_o     = dec_arready & spec_ok & ~dup_match;

    assign hit_flag_fifo_wren  = hs_pulse_delayed;
    assign hit_flag_fifo_wdata = is_hit;

    assign hit_data_fifo_wren  = hs_pulse_delayed & is_hit;
    assign hit_data_fifo_wdata = {offset_delayed, hit_line_data};

    assign miss_req_wdata = new_miss_addr;
    assign miss_req_wren  = new_miss_valid & ~(direct_issue_fire | hold_set);

    assign miss_addr_wdata = new_miss_addr;

    wire miss_meta_push        = new_miss_valid;
    wire ft_miss_addr_valid    = miss_addr_empty & miss_meta_push;

    wire miss_addr_empty_to_fill        = miss_addr_empty & ~ft_miss_addr_valid;
    wire [31:0] miss_addr_rdata_to_fill  = ft_miss_addr_valid ? new_miss_addr : miss_addr_rdata;

    wire fill_miss_addr_rden;
    wire fill_wren;
    wire fill_wway;
    wire [7:0]   fill_waddr;
    wire [18:0]  fill_wtag;
    wire [511:0] fill_wdata;

    CC_DATA_FILL_UNIT u_fill (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .mem_rdata_i            (mem_rdata_i),
        .mem_rlast_i            (mem_rlast_i),
        .mem_rvalid_i           (mem_rvalid_i),
        .mem_rready_i           (mem_rready_o),

        .miss_addr_fifo_empty_i (miss_addr_empty_to_fill),
        .miss_addr_fifo_rdata_i (miss_addr_rdata_to_fill),
        .miss_addr_fifo_rden_o  (fill_miss_addr_rden),

        .wren_o                 (fill_wren),
        .wway_o                 (fill_wway),
        .waddr_o                (fill_waddr),
        .wdata_tag_o            (fill_wtag),
        .wdata_data_o           (fill_wdata)
    );

    assign miss_addr_rden = fill_miss_addr_rden & ~miss_addr_empty;

    wire ft_miss_addr_consume = ft_miss_addr_valid & fill_miss_addr_rden;
    assign miss_addr_wren_to_fifo = miss_meta_push & ~ft_miss_addr_consume;

    assign wren_o       = fill_wren;
    assign wway_o       = fill_wway;
    assign waddr_o      = fill_waddr;
    assign wdata_tag_o  = fill_wtag;
    assign wdata_data_o = fill_wdata;
    // Fill your code here

endmodule