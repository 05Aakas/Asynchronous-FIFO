`timescale 1ns/1ps

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4   // FIFO depth = 2^ADDR_WIDTH
)(
    input  wire                 wr_clk,     // Write clock
    input  wire                 rd_clk,     // Read clock
    input  wire                 rst_n,      // Active-low reset

    input  wire                 wr_en,      // Write enable
    input  wire [DATA_WIDTH-1:0] wr_data,   // Write data
    output wire                 full,       // FIFO full flag

    input  wire                 rd_en,      // Read enable
    output reg  [DATA_WIDTH-1:0] rd_data,   // Read data
    output wire                 empty       // FIFO empty flag
);

    // ============================================================
    // Internal signals
    // ============================================================
    localparam DEPTH = 1 << ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];   // FIFO memory

    // Pointers
    reg [ADDR_WIDTH:0] wr_ptr_bin, rd_ptr_bin;
    reg [ADDR_WIDTH:0] wr_ptr_gray, rd_ptr_gray;
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    // ============================================================
    // Write pointer logic
    // ============================================================
    wire [ADDR_WIDTH:0] wr_ptr_bin_next = wr_ptr_bin + (wr_en & ~full);
    wire [ADDR_WIDTH:0] wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
            if (wr_en & ~full)
                mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    // ============================================================
    // Read pointer logic
    // ============================================================
    wire [ADDR_WIDTH:0] rd_ptr_bin_next = rd_ptr_bin + (rd_en & ~empty);
    wire [ADDR_WIDTH:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
            rd_data     <= 0;
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
            if (rd_en & ~empty)
                rd_data <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
        end
    end

    // ============================================================
    // Pointer synchronization across clock domains
    // ============================================================
    // Sync read pointer into write clock domain
    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // Sync write pointer into read clock domain
    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // ============================================================
    // Full / Empty flag logic
    // ============================================================
    // Convert Gray back to Binary
    function [ADDR_WIDTH:0] gray2bin;
        input [ADDR_WIDTH:0] gray;
        integer i;
        begin
            gray2bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
            for (i = ADDR_WIDTH-1; i >= 0; i = i-1)
                gray2bin[i] = gray2bin[i+1] ^ gray[i];
        end
    endfunction

    wire [ADDR_WIDTH:0] rd_ptr_bin_sync = gray2bin(rd_ptr_gray_sync2);
    wire [ADDR_WIDTH:0] wr_ptr_bin_sync = gray2bin(wr_ptr_gray_sync2);

    assign full  = (wr_ptr_gray_next == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], 
                                         rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});

    assign empty = (rd_ptr_gray_next == wr_ptr_gray_sync2);

endmodule
