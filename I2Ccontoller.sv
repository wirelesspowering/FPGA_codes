`timescale 1ns / 1ps

module I2C_Master (
    input  logic        clk,
    input  logic        rst,
    
    inout  wire         sda,      // Bidirectional SDA with external pullup
    output logic        scl,      // SCL output
    
    // Command interface
    input  logic        start,
    input  logic        rw,       // 0=write, 1=read
    input  logic [6:0]  slave_addr,
    input  logic [7:0]  reg_addr,
    input  logic [7:0]  write_data,
    output logic [7:0]  read_data,
    
    output logic        busy,
    output logic        done,
    output logic        ack_error
);

    // Standard I2C timing parameters (100kHz @ 20MHz clk)
    parameter CLK_DIV = 200;  // 20MHz/200 = 100kHz
    localparam CLK_HALF = CLK_DIV/2;
    
    typedef enum logic [3:0] {
        IDLE,
        START,
        SLAVE_ADDR,
        REG_ADDR,
        WRITE_BYTE,
        READ_BYTE,
        ACK,
        STOP
    } i2c_state_t;
    
    i2c_state_t state, next_state;
    logic [9:0] clk_cnt;
    logic [2:0] bit_cnt;
    logic sda_out_en;
    logic sda_in;
    
    // SDA bidirectional handling
    assign sda = sda_out_en ? 1'b0 : 1'bz;
    assign sda_in = sda;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            scl <= 1'b1;
            sda_out_en <= 1'b1;
            clk_cnt <= 0;
            bit_cnt <= 0;
            busy <= 1'b0;
            done <= 1'b0;
            ack_error <= 1'b0;
            read_data <= 8'h00;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    scl <= 1'b1;
                    sda_out_en <= 1'b1;  // idle high
                    busy <= 1'b0;
                    if (start) begin
                        state <= START;
                        busy <= 1'b1;
                        clk_cnt <= 0;
                    end
                end
                
                START: begin
                    clk_cnt <= clk_cnt + 1;
                    if (clk_cnt == CLK_HALF) scl <= 1'b0;
                    if (clk_cnt == CLK_DIV) begin
                        sda_out_en <= 1'b0;  // SDA low for start
                        clk_cnt <= 0;
                        state <= SLAVE_ADDR;
                        bit_cnt <= 0;
                    end
                end
                
                SLAVE_ADDR: begin
                    send_byte({slave_addr, rw}, SLAVE_ADDR, REG_ADDR);
                end
                
                REG_ADDR: begin
                    send_byte(reg_addr, REG_ADDR, rw ? READ_BYTE : WRITE_BYTE);
                end
                
                WRITE_BYTE: begin
                    send_byte(write_data, WRITE_BYTE, STOP);
                end
                
                READ_BYTE: begin
                    read_byte(READ_BYTE, ACK);
                end
                
                ACK: begin
                    handle_ack(ACK, STOP);
                end
                
                STOP: begin
                    clk_cnt <= clk_cnt + 1;
                    if (clk_cnt == CLK_HALF) scl <= 1'b0;
                    if (clk_cnt == CLK_DIV) begin
                        sda_out_en <= 1'b1;  // SDA high for stop
                        clk_cnt <= 0;
                        state <= STOP;
                    end else if (clk_cnt == CLK_DIV*2) begin
                        state <= IDLE;
                        done <= 1'b1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // Byte transmission helper
    task send_byte(input logic [7:0] data, input i2c_state_t curr, input i2c_state_t next);
        clk_cnt <= clk_cnt + 1;
        if (clk_cnt == CLK_HALF) scl <= 1'b0;
        if (clk_cnt == CLK_DIV/2) begin  // setup time
            if (bit_cnt < 8) begin
                sda_out_en <= ~data[7-bit_cnt];  // MSB first
            end
        end
        if (clk_cnt == CLK_DIV) begin
            scl <= 1'b1;
            if (bit_cnt == 8) begin
                sda_out_en <= 1'b0;  // release for ACK
                bit_cnt <= 0;
                clk_cnt <= 0;
                state <= next;
            end else begin
                bit_cnt <= bit_cnt + 1;
                clk_cnt <= 0;
            end
        end
    endtask
    
    // Byte reception helper
    task read_byte(input i2c_state_t curr, input i2c_state_t next);
        clk_cnt <= clk_cnt + 1;
        if (clk_cnt == CLK_HALF) scl <= 1'b0;
        if (clk_cnt == CLK_DIV) begin
            scl <= 1'b1;
            if (bit_cnt < 8) begin
                read_data[7-bit_cnt] <= sda_in;
                bit_cnt <= bit_cnt + 1;
            end else begin
                bit_cnt <= 0;
                state <= next;
            end
            clk_cnt <= 0;
        end
    endtask
    
    // ACK handling
    task handle_ack(input i2c_state_t curr, input i2c_state_t next);
        clk_cnt <= clk_cnt + 1;
        if (clk_cnt == CLK_DIV) begin
            ack_error <= sda_in;  // ACK = SDA low
            sda_out_en <= 1'b1;   // release SDA
            state <= next;
            clk_cnt <= 0;
        end
    endtask

endmodule
