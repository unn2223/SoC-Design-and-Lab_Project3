module SRAM_DUAL_PORT_ARRAY
(
    input  wire                clk,
    input  wire                rst_n,
    
    input  wire                rden_i,
    input  wire [7:0]          raddr_i,          
    output wire [18:0]         rdata_tag0_o,    
    output wire [18:0]         rdata_tag1_o,    
    output wire [511:0]        rdata_data0_o,   
    output wire [511:0]        rdata_data1_o, 

    input  wire                wren_i,
    input  wire [7:0]          waddr_i,
    input  wire                wway_i,          
    input  wire [18:0]         wdata_tag_i,     
    input  wire [511:0]        wdata_data_i     
);

    reg [18:0]   tag_array  [1:0][255:0];   
    reg [511:0]  data_array [1:0][255:0];

    reg [18:0]   rdata_tag0,  rdata_tag1;
    reg [511:0]  rdata_data0, rdata_data1;

    integer way, idx;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (way = 0; way < 2; way++) begin
                for (idx = 0; idx < 256; idx++) begin
                    tag_array [way][idx] <= {19{1'b0}};
                    data_array[way][idx] <= {512{1'b0}};
                end
            end
            rdata_tag0  <= {19{1'b0}};
            rdata_tag1  <= {19{1'b0}};
            rdata_data0 <= {512{1'b0}};
            rdata_data1 <= {512{1'b0}};
        end
        else begin
            if (rden_i) begin
                rdata_tag0  <= tag_array [0][raddr_i];
                rdata_tag1  <= tag_array [1][raddr_i];
                rdata_data0 <= data_array[0][raddr_i];
                rdata_data1 <= data_array[1][raddr_i];
            end
            else begin
                rdata_tag0  <= 'Z;
                rdata_tag1  <= 'Z;
                rdata_data0 <= 'Z;
                rdata_data1 <= 'Z;
            end

            if (wren_i) begin
                tag_array [wway_i][waddr_i] <= wdata_tag_i;
                data_array[wway_i][waddr_i] <= wdata_data_i;
            end
        end
    end

    assign rdata_tag0_o  = rdata_tag0;
    assign rdata_tag1_o  = rdata_tag1;
    assign rdata_data0_o = rdata_data0;
    assign rdata_data1_o = rdata_data1;
endmodule
