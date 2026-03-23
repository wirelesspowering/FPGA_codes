module PLL_Power_Sequencer (
    input  logic        clk,
    input  logic        rst,
    
    output logic        pll_power_ready,
    
    // I2C interface signals
    inout  wire         i2c_sda,
    output logic        i2c_scl
);

    // IO expander addresses: 0x20, 0x21, 0x22, 0x23
    localparam [6:0] EXP_ADDR [3:0] = '{7'h20, 7'h21, 7'h22, 7'h23};
    
    // MCP23008 register map (adjust if different chip)
    localparam [7:0] IODIR_REG  = 8'h00;  // Direction register
    localparam [7:0] GPIO_REG   = 8'h09;  // Output register
    
    // Example: GP0=power EN, GP1=reset_n, GP2=CS_enable (all active high)
    localparam [7:0] POWER_MASK = 8'h07;
    
    typedef enum logic [4:0] {
        PWR_IDLE,
        PWR_CFG_DIR0, PWR_EN0,
        PWR_CFG_DIR1, PWR_EN1,
        PWR_CFG_DIR2, PWR_EN2,
        PWR_CFG_DIR3, PWR_EN3,
        PWR_STABILIZE,
        PWR_READY
    } pwr_state_t;
    
    pwr_state_t state;
    logic [2:0] current_pll;
    logic [23:0] stabilize_cnt;
    
    // I2C master signals
    logic i2c_start, i2c_rw, i2c_done, i2c_busy, i2c_ack_error;
    logic [6:0] i2c_slave_addr;
    logic [7:0] i2c_reg_addr, i2c_write_data;
    
    I2C_Master i2c_master (
        .clk(clk),
        .rst(rst),
        .sda(i2c_sda),
        .scl(i2c_scl),
        .start(i2c_start),
        .rw(i2c_rw),
        .slave_addr(i2c_slave_addr),
        .reg_addr(i2c_reg_addr),
        .write_data(i2c_write_data),
        .busy(i2c_busy),
        .done(i2c_done),
        .ack_error(i2c_ack_error)
    );
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= PWR_IDLE;
            pll_power_ready <= 1'b0;
            current_pll <= 0;
            stabilize_cnt <= 0;
            i2c_start <= 1'b0;
        end else begin
            i2c_start <= 1'b0;
            
            case (state)
                PWR_IDLE: begin
                    pll_power_ready <= 1'b0;
                    current_pll <= 0;
                    state <= PWR_CFG_DIR0;
                end
                
                PWR_CFG_DIR0, PWR_CFG_DIR1, PWR_CFG_DIR2, PWR_CFG_DIR3: begin
                    if (!i2c_busy) begin
                        i2c_slave_addr <= EXP_ADDR[current_pll];
                        i2c_reg_addr   <= IODIR_REG;
                        i2c_write_data <= 8'h00;  // All outputs
                        i2c_rw         <= 1'b0;
                        i2c_start      <= 1'b1;
                    end else if (i2c_done) begin
                        if (!i2c_ack_error) begin
                            state <= state + 1;  // Next step (EN)
                        end
                    end
                end
                
                PWR_EN0, PWR_EN1, PWR_EN2, PWR_EN3: begin
                    if (!i2c_busy) begin
                        i2c_slave_addr <= EXP_ADDR[current_pll];
                        i2c_reg_addr   <= GPIO_REG;
                        i2c_write_data <= POWER_MASK;  // Enable power/reset/CS
                        i2c_rw         <= 1'b0;
                        i2c_start      <= 1'b1;
                    end else if (i2c_done) begin
                        if (!i2c_ack_error && current_pll < 3) begin
                            current_pll <= current_pll + 1;
                            state <= PWR_CFG_DIR0 + (current_pll << 1) + 2;
                        end else if (!i2c_ack_error) begin
                            // All 4 PLLs powered
                            stabilize_cnt <= 0;
                            state <= PWR_STABILIZE;
                        end
                    end
                end
                
                PWR_STABILIZE: begin
                    stabilize_cnt <= stabilize_cnt + 1;
                    if (stabilize_cnt == 24'd10000000) begin  // ~500ms @ 20MHz
                        pll_power_ready <= 1'b1;
                        state <= PWR_READY;
                    end
                end
                
                PWR_READY: begin
                    pll_power_ready <= 1'b1;
                end
                
                default: state <= PWR_IDLE;
            endcase
        end
    end

endmodule