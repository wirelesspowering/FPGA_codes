`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/23/2023 03:42:20 PM
// Design Name: 
// Module Name: uartInterface
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

module uartInterface(
    input uartRx,
    output reg uartTx,
    input clk,
    input rst,
    input [47:0] txData,
    output reg [47:0] rxData,
    output reg [1:0] size,
    output reg readWRITE,
    output reg [15:0] readLen,
    output reg startCommand,
    output reg [4:0] address,
    input readDataReady,
    output reg readDone,
    // NEW: PLL select output
    output reg [1:0] pll_sel,     // PLL 0-3
    output reg resetDUT = 0
    );
    //localparam DIV_RATIO = 174; //20MHz / (174) approx 115.2kbaud    
    localparam DIV_RATIO = 87; //10MHz / (87) approx 115.2kbaud    
    localparam OVERSAMPLE = 6; 
    localparam OVERSAMPLE_OFFSET = 0;
    localparam TIMEOUT = 60; // 6 bit max
    localparam DIV_COUNT = int'(DIV_RATIO / (OVERSAMPLE));
   
    reg[11:0] divCounter = 0;
    reg uartClk = 0;
   
    // Standard Write Command format: Command (8bit), Address (8bit), Data (8/16/24/48 bit)
    // Standard Read Command format: Command (8bit), Address (8bit)
    // Continuous Read: Command (8bit), Address (8bit), Length (16 bit)
   
    typedef enum reg[7:0] {
        READ_8 = 8'd0,
        READ_16 = 8'd1,
        READ_24 = 8'd2,
        READ_48 = 8'd3,
        WRITE_8 = 8'd4,
        WRITE_16 = 8'd5,
        WRITE_24 = 8'd6,
        WRITE_48 = 8'd7,
        READ_8_CONT = 8'd8,
        READ_16_CONT = 8'd9,
        READ_24_CONT = 8'd10,
        READ_48_CONT = 8'd11,
        RESET_DUT = 8'd12,
        INVALID = 8'd13,
        MAXVAL = 8'd255
        } uCommand;
    uCommand currCommand; 
        
    typedef enum reg[1:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP} txState;
    typedef enum reg[2:0] {RX_IDLE, RX_START_CMD, RX_DATA_CMD, RX_STOP_CMD, RX_START_VAL, RX_DATA_VAL, RX_STOP_VAL, RX_RESTART_VAL} rxState;
    txState uartTxState = TX_IDLE;
    rxState uartRxState = RX_IDLE;
    reg [7:0] txBuf [5:0];
    reg [7:0] rxBuf [7:0]; 
    

    
    reg rxLast = 1'b1;
    reg [3:0] rxPtr;
    reg [2:0] rxByteCount;
    reg [2:0] rxByteCountMax = 0;
    reg [5:0] rxOSCnt; //Oversample Counter 
    reg [3:0] txPtr;
    reg [4:0] txOSCnt;
    reg [2:0] txLen; 
    reg [2:0] txCnt;

    assign txLen = 3'd6;
    
    always_ff @ (posedge clk) begin
        if(divCounter == DIV_COUNT) begin
            uartClk <= 1'b1;
            divCounter <= 0;
        end else begin
            uartClk <= 1'b0;
            divCounter <= divCounter + 1;
        end
    end
        
    //RX Controller
    always_ff @ (posedge clk, posedge rst) begin
    if (rst == 1'b1) begin
        uartRxState <= RX_IDLE;
        rxPtr <= 0;
        rxByteCount <= 0;
        rxLast <= 1'b1;
        rxOSCnt <= 0;
        readLen <= 1;
        currCommand <= INVALID;
        startCommand <= 1'b0;
        resetDUT <= 0;
        pll_sel <= 2'b00;        // NEW: Default PLL0
    end else if (uartClk == 1'b1) begin
        rxLast <= uartRx;
        case(uartRxState)
        RX_IDLE: begin
            if(rxLast == 1'b1 && uartRx == 1'b0) begin
                uartRxState <= RX_START_CMD;
            end else begin
                uartRxState <= RX_IDLE;
            end
            rxByteCount <= 0;
            rxOSCnt <= 0;
            rxPtr <= 0;        
            startCommand <= 1'b0;
            resetDUT <= 0;
        end
        RX_START_CMD: begin
            if(rxOSCnt >= (OVERSAMPLE + OVERSAMPLE_OFFSET)) begin
                uartRxState <= RX_DATA_CMD;
                rxOSCnt <= 0;
            end else begin
                uartRxState <= RX_START_CMD; 
                rxOSCnt <= rxOSCnt + 1;
            end
            rxPtr <= 0;
        end
        RX_DATA_CMD: begin
            if(rxOSCnt == 0) begin
                rxBuf[0][rxPtr] <= uartRx;
                rxPtr <= rxPtr + 1;
            end
            if(rxOSCnt >= (OVERSAMPLE-1)) begin
                if(rxPtr < 8) begin
                    uartRxState <= RX_DATA_CMD;
                end else begin
                    uartRxState <= RX_STOP_CMD;
                end
                rxOSCnt <= 0;    
            end else begin
                uartRxState <= RX_DATA_CMD; 
                rxOSCnt <= rxOSCnt + 1;
            end
        end
        RX_STOP_CMD: begin
            if(rxOSCnt == 0) begin
                if(uartRx != 1'b1) begin //Framing error
                    uartRxState <= RX_IDLE;
                    currCommand <= INVALID;
                 end else if (rxBuf[0] >= INVALID) begin //Not a valid command
                    uartRxState <= RX_IDLE;
                    currCommand <= INVALID;
                 end else begin
                    currCommand <= uCommand'(rxBuf[0]);
                    unique case(uCommand'(rxBuf[0]))
                        READ_8 : begin
                            size <= 2'b00;
                            rxByteCountMax <= 3'd1;
                            readWRITE <= 0;                            
                        end
                        READ_16 : begin
                            size <= 2'b01;
                            rxByteCountMax <= 3'd1; 
                            readWRITE <= 0;                       
                        end
                        READ_24 : begin
                            size <= 2'b10;
                            rxByteCountMax <= 3'd1;   
                            readWRITE <= 0;                     
                        end
                        READ_48 : begin
                            size <= 2'b11;
                            rxByteCountMax <= 3'd1;      
                            readWRITE <= 0;                  
                        end
                        WRITE_8 : begin
                            size <= 2'b00;
                            rxByteCountMax <= 3'd2;
                            readWRITE <= 1'b1;
                        end
                        WRITE_16 : begin
                            size <= 2'b01;
                            rxByteCountMax <= 3'd3;   
                            readWRITE <= 1'b1;                     
                        end
                        WRITE_24 : begin
                            size <= 2'b10;
                            rxByteCountMax <= 3'd4;    
                            readWRITE <= 1'b1;                    
                        end
                        WRITE_48 : begin
                            size <= 2'b11;
                            rxByteCountMax <= 3'd7;    
                            readWRITE <= 1'b1;                    
                        end
                        READ_8_CONT : begin
                            size <= 2'b00;
                            rxByteCountMax <= 3'd3;  
                            readWRITE <= 0;                         
                        end
                        READ_16_CONT : begin
                            size <= 2'b01;
                            rxByteCountMax <= 3'd3;   
                            readWRITE <= 0;                        
                        end
                        READ_24_CONT : begin
                            size <= 2'b10;
                            rxByteCountMax <= 3'd3;    
                            readWRITE <= 0;                       
                        end
                        READ_48_CONT : begin
                            size <= 2'b11;
                            rxByteCountMax <= 3'd3;   
                            readWRITE <= 0;                        
                        end
                        RESET_DUT : begin
                            size <= 2'b00;
                            rxByteCountMax <= 3'd1;
                            readWRITE <= 0;
                            resetDUT <= 1'b1;
                        end
                    endcase
                 end
                 rxOSCnt <= rxOSCnt + 1;
            end else if(rxOSCnt >= TIMEOUT) begin //Timeout
                uartRxState <= RX_IDLE;
                rxOSCnt <= 0;
            end else if (rxLast == 1'b1 && uartRx == 1'b0) begin //Next Start Bit
                uartRxState <= RX_START_VAL; 
                rxOSCnt <= 0;
            end else begin
                uartRxState <= RX_STOP_CMD;
                rxOSCnt <= rxOSCnt + 1;
            end
        end
        RX_START_VAL: begin
            if(rxOSCnt >= (OVERSAMPLE + OVERSAMPLE_OFFSET)) begin
                uartRxState <= RX_DATA_VAL;
                rxOSCnt <= 0;
            end else begin
                uartRxState <= RX_START_VAL; 
                rxOSCnt <= rxOSCnt + 1;
            end
            rxPtr <= 0;
        end
        RX_DATA_VAL: begin
            if(rxOSCnt == 0) begin
                rxBuf[rxByteCount+1][rxPtr] <= uartRx;
                rxPtr <= rxPtr + 1;
            end
            if(rxOSCnt >= (OVERSAMPLE-1)) begin                
                if(rxPtr < 8) begin
                    uartRxState <= RX_DATA_VAL;
                end else begin
                    rxByteCount = rxByteCount + 1;
                    uartRxState <= RX_STOP_VAL;
                end
                rxOSCnt <= 0;
            end else begin
                uartRxState <= RX_DATA_VAL; 
                rxOSCnt <= rxOSCnt + 1;
            end
        end
        RX_STOP_VAL: begin
            if(uartRx != 1'b1) begin //Framing error
                currCommand <= INVALID;
                uartRxState <= RX_IDLE;
            end else if(rxByteCount < rxByteCountMax) begin
                uartRxState <= RX_RESTART_VAL;
            end else begin
                startCommand <= 1'b1;
                // NEW: Parse pll_sel from rxBuf[0] high bits or rxBuf[1]
                pll_sel <= rxBuf[0][7:6];    // Bits 7:6 of command byte = PLL select
                Temp variable for immediate case use
                uCommand parsed_cmd = uCommand'(rxBuf[0][5:0]);
                currCommand <= parsed_cmd;  // Latch for next time
                address <= rxBuf[1][4:0];    
                uartRxState <= RX_IDLE;
                readLen <= 1;
                case(parsed_cmd)
                    WRITE_8 : begin
                        rxData[47:8] <= 0;
                        rxData[7:0] <= rxBuf[2];
                    end
                    WRITE_16 : begin
                        rxData[47:16] <= 0;
                        rxData[15:0] <= {rxBuf[2], rxBuf[3]};                 
                    end
                    WRITE_24 : begin
                        rxData[47:24] <= 0;
                        rxData[23:0] <= {rxBuf[2], rxBuf[3], rxBuf[4]};                     
                    end
                    WRITE_48 : begin
                        rxData <= {rxBuf[2], rxBuf[3], rxBuf[4], rxBuf[5], rxBuf[6], rxBuf[7]};  
                    end
                    READ_8_CONT,READ_16_CONT,READ_24_CONT,READ_48_CONT : begin
                        readLen <= {rxBuf[2], rxBuf[3]};                  
                    end
                    default : begin                      
                    end
                endcase
            end
        end
        RX_RESTART_VAL : begin
            if(rxOSCnt >= TIMEOUT) begin //Timeout
                uartRxState <= RX_IDLE;
                rxOSCnt <= 0;
            end else if (rxLast == 1'b1 && uartRx == 1'b0) begin //Next Start Bit
                uartRxState <= RX_START_VAL; 
                rxOSCnt <= 0;
            end else begin
                uartRxState <= RX_RESTART_VAL;
                rxOSCnt <= rxOSCnt + 1;
            end
        end
        
        default: begin
            currCommand <= INVALID;
            uartRxState <= RX_IDLE;
        end
        endcase
    end else begin
        startCommand <= 1'b0;
    end
    end
    
    //TX Controller    
    always_ff @ (posedge clk, posedge rst) begin
    if(rst == 1'b1) begin
        uartTx <= 1'b1;
        uartTxState <= TX_IDLE;
        txPtr <= 0;
        txCnt <= 0;
        txOSCnt <= 0;
        readDone <= 0;
    end else if(uartClk == 1'b1) begin
        case(uartTxState) 
        TX_IDLE: begin
            uartTxState <= (readDataReady == 1'b1) ? TX_START : TX_IDLE; 
            uartTx <= 1'b1;
            txPtr <= 0;
            txOSCnt <= 0;
            txCnt <= 0;
            if(readDataReady == 1'b1) begin
                readDone <= 1'b1;
                txBuf[0] = txData[47:40];
                txBuf[1] = txData[39:32];
                txBuf[2] = txData[31:24];
                txBuf[3] = txData[23:16];
                txBuf[4] = txData[15:8];
                txBuf[5] = txData[7:0];
                uartTxState <= TX_START;
            end else begin
                readDone <= 1'b0;
                uartTxState <= TX_IDLE;
            end
        end
        TX_START: begin
            readDone <= 1'b0;
            if(txOSCnt >= (OVERSAMPLE-1)) begin
                uartTxState <= TX_DATA;
                txOSCnt <= 0;
            end else begin
                uartTxState <= TX_START;
                txOSCnt <= txOSCnt + 1;
            end
            txPtr <= 0;
            uartTx <= 1'b0;
        end
        TX_DATA: begin
            uartTx <= txBuf[txCnt][txPtr]; 
            if(txOSCnt >= (OVERSAMPLE-1)) begin
                txOSCnt <= 0;
                if(txPtr >= 7) begin
                    txPtr <= 0;
                    uartTxState <= TX_STOP;
                end else begin
                    txPtr <= txPtr + 1;
                    uartTxState <= TX_DATA;
                end
            end else begin
                uartTxState <= TX_DATA;
                txOSCnt <= txOSCnt + 1;
            end
        end
        TX_STOP: begin
            uartTx <= 1'b1;
            if(txOSCnt >= (OVERSAMPLE-1)) begin
                txOSCnt <= 0;
                if(txCnt >= (txLen-1)) begin
                    uartTxState <= TX_IDLE;
                    txCnt <= 0;
                end else begin
                    uartTxState <= TX_START;
                    txCnt <= txCnt + 1;
                end
            end else begin
               uartTxState <= TX_STOP;
               txOSCnt <= txOSCnt + 1;
            end
        end
        default: begin
            uartTxState <= TX_IDLE;
        end
        endcase
    end else begin
        readDone <= 1'b0;
    end
    end
    
    
endmodule  