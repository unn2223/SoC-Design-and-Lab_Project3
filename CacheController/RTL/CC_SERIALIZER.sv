// Copyright (c) 2022 Sungkyunkwan University

module CC_SERIALIZER
(
    input   wire            clk,
    input   wire            rst_n,

    input   wire            fifo_empty_i,
    input   wire            fifo_aempty_i,
    input   wire    [517:0] fifo_rdata_i,
    output  wire            fifo_rden_o,

    output  wire    [63:0]  rdata_o,
    output  wire            rlast_o,
    output  wire            rvalid_o,
    input   wire            rready_i
);

    typedef enum logic [0:0] {S_IDLE=1'b0, S_SEND=1'b1} state_t;
    state_t state_q, state_n;

    logic [511:0] line_buf;
    logic [2:0]   base_word_buf;
    logic [2:0]   beat_cnt_q, beat_cnt_n;

    assign fifo_rden_o = (state_q == S_IDLE) & ~fifo_empty_i;
    wire load_fire = fifo_rden_o & ~fifo_empty_i;

    wire idle_has_data = (state_q == S_IDLE) & ~fifo_empty_i;
    assign rvalid_o = (state_q == S_SEND) | idle_has_data;

    wire out_fire = rvalid_o & rready_i;

    always_comb begin
        state_n    = state_q;
        beat_cnt_n = beat_cnt_q;

        unique case (state_q)
            S_IDLE: begin
                if (~fifo_empty_i) begin
                    state_n    = S_SEND;
                    beat_cnt_n = out_fire ? 3'd1 : 3'd0;
                end else begin
                    state_n    = S_IDLE;
                    beat_cnt_n = 3'd0;
                end
            end

            S_SEND: begin
                if (out_fire) begin
                    if (beat_cnt_q == 3'd7) begin
                        state_n    = S_IDLE;
                        beat_cnt_n = 3'd0;
                    end else begin
                        beat_cnt_n = beat_cnt_q + 3'd1;
                    end
                end
            end

            default: begin
                state_n    = S_IDLE;
                beat_cnt_n = 3'd0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q       <= S_IDLE;
            beat_cnt_q    <= 3'd0;
            line_buf      <= '0;
            base_word_buf <= 3'd0;
        end else begin
            state_q    <= state_n;
            beat_cnt_q <= beat_cnt_n;

            if (load_fire) begin
                line_buf      <= fifo_rdata_i[511:0];
                base_word_buf <= fifo_rdata_i[517:515];
            end
        end
    end

    logic [511:0] line_sel;
    logic [2:0]   base_sel;
    logic [2:0]   beat_sel;

    always_comb begin
        if (state_q == S_SEND) begin
            line_sel = line_buf;
            base_sel = base_word_buf;
            beat_sel = beat_cnt_q;
        end else if (~fifo_empty_i) begin
            line_sel = fifo_rdata_i[511:0];
            base_sel = fifo_rdata_i[517:515];
            beat_sel = 3'd0;
        end else begin
            line_sel = 512'd0;
            base_sel = 3'd0;
            beat_sel = 3'd0;
        end
    end

    wire [2:0] word_idx = base_sel + beat_sel;
    wire [8:0] bit_idx  = {word_idx, 6'b0};

    assign rdata_o = rvalid_o ? line_sel[bit_idx +: 64] : 64'd0;
    assign rlast_o = (state_q == S_SEND) & (beat_cnt_q == 3'd7);

    // Fill the code here

endmodule