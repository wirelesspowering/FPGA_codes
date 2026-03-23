`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/22/2024 01:19:21 PM
// Design Name: 
// Module Name: top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module top(
    input clk12MHz,
    input [1:0] btn,
    output [3:0] led,
    output led0_r,
    output led0_g,
    output led0_b,
    output uart_tx,
    input uart_rx,
    output MOSI,
    input MISO,
    output SCK,
    output CS,
    output NRST_PLL,
    output logic [4:0] pio,
    input logic [8:5] pio,
    output logic ja5,
    output logic ja6,
    //I2C pins
    inout  wire i2c_sda, 
    output wire i2c_scl    
    );
    //reg MISO;
    assign ja5 = uart_tx;
    assign ja6 = uart_rx;
    
    assign pio[0] = CS;
    assign pio[1] = SCK;
    assign pio[2] = MOSI;
    //assign pio[3] = MISO;
    //New pin updates
    //muxed PLL input pins
    assign pll_miso_in[0] = pio[5];  // PLL0 MISO
    assign pll_miso_in[1] = pio[6];  // PLL1
    assign pll_miso_in[2] = pio[7];  // PLL2
    assign pll_miso_in[3] = pio[8];  // PLL3

    
    /* MISO Test Code
    reg [7:0] SPIVAL = 8'h00;
    reg [2:0] SPICNT = 0;
    always @ (posedge SCK) begin
        if(SPICNT == 3'h0) begin
                SPIVAL <= SPIVAL + 1;
        end
        if(CS == 1'b0) begin
            SPICNT <= SPICNT - 1;      
        end else begin
            SPICNT <= 3'h7;
        end
    end 
    assign MISO = SPIVAL[SPICNT];
    */        
    
    wire rst;
    assign rst = btn[0];
    
    //RGB unused, need to drive high
    assign led0_b = 1'b1;
    assign led0_g = 1'b1;
    
    wire clk20MHz;
    clk_gen _clk_gen(
        .clk_out1(clk20MHz),
        .reset(rst),
        .locked(led0_r),
        .clk_in1(clk12MHz)
    );
    
    
    wire readWRITE;
    wire [1:0] size;
    wire [1:0] pll_sel;
    wire [4:0] address;
    wire [47:0] dataWrite;
    wire [47:0] dataRead;
    wire startCommand;
    wire readDataReady;
    wire [15:0] readLen;
    wire [47:0] txData;
    wire readDone;
    wire uartDataReady;
    //PLL powr done flag
    wire pll_power_ready;
    reg [2:0] srst = 3'b111;
    
    
        
    always @ (posedge clk20MHz, posedge rst) begin
        if(rst == 1'b1) begin
            srst <= 3'b111;
        end else begin
            srst[1:0] <= srst[2:1];
            srst[2] <= 1'b0;
        end    
    end
    
    SPIController_4PLL _SPIController(
    .clk(clk20MHz),
    .rst(rst),
    .pll_power_ready(pll_power_ready),
    //.MISO(MISO),
    .pll_sel(pll_sel),
    .pll_miso(pll_miso_in)
    .MOSI(MOSI),
    .CS(CS),
    .SCK(SCK),
    .readWRITE(readWRITE),
    .size(size),
    .address(address),
    .dataWrite(dataWrite),
    .dataRead(dataRead),
    .startCommand(startCommand),
    .readDataReady(readDataReady),
    .readLen(readLen)
    );
    
    fifo_generator_0 _fifo_generator_0(
        .clk(clk20MHz),
        .srst(srst[0]),
        .full(led[1]),
        .din(dataRead),
        .wr_en(readDataReady),
        .empty(led[2]),
        .dout(txData),
        .rd_en(readDone),
        .valid(uartDataReady)
    );
    
    wire resetDUT;
    uartInterface _uartInterface(
        .uartRx(uart_rx),
        .uartTx(uart_tx),
        .clk(clk20MHz),
        .rst(rst),
        .txData(txData),
        .rxData(dataWrite),
        .size(size),
        .readWRITE(readWRITE),
        .readLen(readLen),
        .startCommand(startCommand),
        .address(address),
        .readDataReady(uartDataReady),
        .readDone(readDone),
        .pll_sel(pll_sel),//Added
        .resetDUT(resetDUT)
    );
    
    //Power up sequence to all the PLLs via IO expander
    // Instantiate
    PLL_Power_Sequencer power_seq (
        .clk(clk20MHz),
        .rst(rst),
        .pll_power_ready(pll_power_ready),
        .i2c_sda(i2c_sda),
        .i2c_scl(i2c_scl)
    );

    assign led[0] = ~CS;
    assign led[3] = ~uart_tx | ~uart_rx;
    assign NRST_PLL = ~(rst | resetDUT);
    
    //assign spi_start_gated = startCommand & pll_power_ready;
    assign pio[3] = i2c_scl;  // Wire to PIO
    assign pio[4] = i2c_sda;
    
endmodule
