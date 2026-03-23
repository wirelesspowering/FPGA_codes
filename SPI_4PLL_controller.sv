`timescale 1ns / 1ps

module SPIController_4PLL(
    input wire clk,
    input wire rst,
    input wire pll_power_ready,       // NEW: Gate SPI until power-up done
    input wire [1:0] pll_sel,         // NEW: PLL 0-3 select
    input wire [3:0] pll_miso,        // NEW: Individual MISO inputs
    output reg MOSI,
    output reg CS,                    // Now global CS to all boards
    output reg SCK,
    input wire readWRITE,
    input wire [15:0] readLen,
    input wire [1:0] size,
    input wire [4:0] address,
    input wire [47:0] dataWrite,
    output reg [47:0] dataRead,
    input wire startCommand,
    output reg readDataReady
);

    typedef enum {
        IDLE, COMMAND, WRITE, READ_WAIT, READ_START, IDLE_WAIT
    } SPISTATE;
    SPISTATE spiState = IDLE;
    
    reg [47:0] dataWriteBuf = 0;
    reg [47:0] dataReadBuf = 0;
    reg [1:0] sizeBuf = 0;
    reg [4:0] addressBuf = 0;
    reg [15:0] readLenBuf = 0;
    reg readWRITEBuf;
    reg [1:0] pll_sel_buf;              // NEW: Latched PLL select
    
    wire [7:0] command;
    assign command = {readWRITEBuf, sizeBuf, addressBuf};
    
    reg SCK_En = 0;
    assign SCK = clk | ~SCK_En;
    
    reg [5:0] txrxIndex = 0;
    
    // NEW: MISO mux - only selected PLL's MISO
    wire miso_selected;
    assign miso_selected = pll_miso[pll_sel_buf];
    
    always @ (negedge clk, posedge rst) begin
        if(rst == 1'b1) begin
            dataRead = '0;
            MOSI = 1'b1;
            CS = 1'b1;
            SCK_En = 1'b0;
            readDataReady = 1'b0;
            spiState = IDLE;
            pll_sel_buf = 2'b00;    // NEW
        end else begin
            case(spiState)
                IDLE : begin
                    SCK_En <= 1'b0;
                    readDataReady <= 1'b0;
                    // CHANGED: Add pll_power_ready gate + latch pll_sel
                    if(startCommand == 1'b1 && pll_power_ready == 1'b1) begin
                        dataWriteBuf <= dataWrite;
                        dataReadBuf <= 0;
                        sizeBuf <= size;
                        addressBuf <= address;
                        readLenBuf <= (readLen == 0) ? 16'd1 : readLen;
                        readWRITEBuf <= readWRITE;
                        pll_sel_buf <= pll_sel;     // NEW: Latch PLL select
                        txrxIndex <= 6'd7;
                        CS <= 1'b0;                 // Global CS active
                        spiState <= COMMAND;
                    end else begin
                        spiState <= IDLE;
                        CS <= 1'b1;
                        MOSI <= 1'b1;
                    end
                end
                
                COMMAND : begin
                    SCK_En <= 1'b1;
                    CS <= 1'b0;                 // Keep global CS low
                    MOSI <= command[txrxIndex];
                    if(txrxIndex > 0) begin    
                        spiState <= COMMAND;
                        txrxIndex <= txrxIndex - 1;
                    end else begin
                        unique case(sizeBuf)
                            2'b00 : txrxIndex <= 6'd7;
                            2'b01 : txrxIndex <= 6'd15;
                            2'b10 : txrxIndex <= 6'd23;
                            2'b11 : txrxIndex <= 6'd47;
                        endcase             
                        if(readWRITEBuf == 1'b0) begin
                            spiState <= READ_WAIT;
                            readLenBuf <= readLenBuf - 1;
                        end else begin
                            spiState <= WRITE;
                        end
                    end 
                end
                
                WRITE : begin
                    SCK_En <= 1'b1;
                    CS <= 1'b0;
                    MOSI <= dataWriteBuf[txrxIndex];
                    if(txrxIndex > 0) begin    
                        spiState <= WRITE;
                        txrxIndex <= txrxIndex - 1;
                    end else begin
                        spiState <= IDLE_WAIT;
                        txrxIndex <= 7;
                    end
                end
                
                READ_WAIT : begin
                    SCK_En <= 1'b1;
                    CS <= 1'b0;
                    spiState <= READ_START;
                end
                
                READ_START : begin
                    SCK_En <= 1'b1;
                    CS <= 1'b0;
                    // CHANGED: Use muxed MISO instead of single MISO
                    dataReadBuf[txrxIndex] <= miso_selected;
                    if(txrxIndex > 0) begin    
                        spiState <= READ_START;
                        txrxIndex <= txrxIndex - 1;
                        readDataReady <= 1'b0;
                    end else if(readLenBuf > 0) begin
                        readLenBuf <= readLenBuf - 1;
                        spiState <= READ_START;
                        unique case(sizeBuf)
                            2'b00 : txrxIndex <= 6'd7;
                            2'b01 : txrxIndex <= 6'd15;
                            2'b10 : txrxIndex <= 6'd23;
                            2'b11 : txrxIndex <= 6'd47;
                        endcase
                        dataRead[47:1] <= dataReadBuf[47:1];
                        dataRead[0] <= miso_selected;   // CHANGED
                        readDataReady <= 1'b1;
                    end else begin
                        spiState <= IDLE_WAIT;
                        txrxIndex <= 7;
                        dataRead[47:1] <= dataReadBuf[47:1];
                        dataRead[0] <= miso_selected;   // CHANGED
                        readDataReady <= 1'b1;
                    end
                end
                
                IDLE_WAIT : begin
                    CS <= 1'b0;
                    readDataReady <= 1'b0;
                    if(txrxIndex < 3) begin
                        CS <= 1'b1;
                    end
                    if(txrxIndex > 0) begin
                        txrxIndex <= txrxIndex - 1;
                        spiState <= IDLE_WAIT;
                    end else begin
                        spiState <= IDLE;
                    end
                end
                
                default : begin
                    CS <= 1'b1;
                    spiState <= IDLE;
                end
            endcase
        end 
    end
endmodule
