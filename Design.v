module spi_top #(
  parameter CLK_DIV = 4
)(
  input  logic        clk,
  input  logic        rst_n,

  // Config
  input  logic        cpol,
  input  logic        cpha,
  input  logic        width_sel,

  // Master control
  input  logic        start,
  output logic        done_master,
  output logic        busy_master,

  // Master TX / Slave RX
  input  logic [15:0] master_tx_data,
  output logic [15:0] slave_rx_data,

  // Slave TX / Master RX
  input  logic [15:0] slave_tx_data,
  output logic [15:0] master_rx_data,

  // Status
  output logic        done_slave,
  output logic        busy_slave
);

  
  // Internal SPI bus signals (loopback wires)
  
  logic sclk;
  logic cs_n;
  logic mosi;
  logic miso;

  
  // SPI Master
  
  spi_master #(
    .CLK_DIV(CLK_DIV)
  ) u_master (
    .clk        (clk),
    .rst_n      (rst_n),
    .cpol       (cpol),
    .cpha       (cpha),
    .width_sel  (width_sel),
    .start      (start),
    .done       (done_master),
    .busy       (busy_master),
    .tx_data    (master_tx_data),
    .rx_data    (master_rx_data),
    .sclk       (sclk),
    .cs_n       (cs_n),
    .mosi       (mosi),
    .miso       (miso)
  );

  
  // SPI Slave
 
  spi_slave u_slave (
    .clk        (clk),
    .rst_n      (rst_n),
    .cpol       (cpol),
    .cpha       (cpha),
    .width_sel  (width_sel),
    .tx_data    (slave_tx_data),
    .rx_data    (slave_rx_data),
    .done       (done_slave),
    .busy       (busy_slave),
    .sclk       (sclk),
    .cs_n       (cs_n),
    .mosi       (mosi),
    .miso       (miso)
  );

endmodule

module spi_master #(
  parameter CLK_DIV = 4   // SCLK = sys_clk / (2 * CLK_DIV)
)(
  input  logic        clk,
  input  logic        rst_n,

  // Config
  input  logic        cpol,      // clock polarity
  input  logic        cpha,      // clock phase
  input  logic        width_sel, // 0 = 8-bit, 1 = 16-bit

  // Control
  input  logic        start,
  output logic        done,
  output logic        busy,

  // Data
  input  logic [15:0] tx_data,
  output logic [15:0] rx_data,

  // SPI bus
  output logic        sclk,
  output logic        cs_n,
  output logic        mosi,
  input  logic        miso
);

  
  // Internal signals
 
  typedef enum logic [1:0] {IDLE, TRANSFER, DONE} state_t;
  state_t state;

  logic [$clog2(CLK_DIV)-1:0] clk_cnt;   // clock divider counter
  logic                        sclk_int;  // internal SCLK before CPOL
  logic [4:0]                  bit_cnt;   // counts bits shifted (max 16)
  logic [4:0]                  total_bits;// 8 or 16
  logic [15:0]                 shift_tx;  // TX shift register
  logic [15:0]                 shift_rx;  // RX shift register
  logic                        clk_edge;  // pulses every SCLK half-period
  logic                        sclk_prev; // for edge detection

  assign total_bits = width_sel ? 5'd16 : 5'd8;

  
  // Clock divider - generates clk_edge pulse
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      clk_cnt  <= '0;
      clk_edge <= 1'b0;
    end
    else if (state == TRANSFER) begin
      if (clk_cnt == CLK_DIV - 1) begin
        clk_cnt  <= '0;
        clk_edge <= 1'b1;
      end
      else begin
        clk_cnt  <= clk_cnt + 1;
        clk_edge <= 1'b0;
      end
    end
    else begin
      clk_cnt  <= '0;
      clk_edge <= 1'b0;
    end
  end

  
  // SCLK generation
  
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      sclk_int <= 1'b0;
    else if (state == IDLE)
      sclk_int <= cpol;       // idle state defined by CPOL
    else if (state == TRANSFER && clk_edge)
      sclk_int <= ~sclk_int;  // toggle
  end

  assign sclk = sclk_int;

  // edge detection for shift/sample logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) sclk_prev <= 1'b0;
    else        sclk_prev <= sclk_int;
  end

  wire sclk_rising  = ( sclk_int && !sclk_prev);
  wire sclk_falling = (!sclk_int &&  sclk_prev);

  // -------------------------------------------------------
  // Main FSM
  // -------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= IDLE;
      cs_n     <= 1'b1;
      mosi     <= 1'b0;
      bit_cnt  <= '0;
      shift_tx <= '0;
      shift_rx <= '0;
      rx_data  <= '0;
      done     <= 1'b0;
      busy     <= 1'b0;
    end
    else begin
      done <= 1'b0; // default

      case (state)

        IDLE: begin
          cs_n <= 1'b1;
          busy <= 1'b0;
          if (start) begin
    shift_tx <= width_sel ? tx_data : {tx_data[7:0], 8'h00};
    bit_cnt  <= '0;
    cs_n     <= 1'b0;
    busy     <= 1'b1;
    state    <= TRANSFER;
    mosi     <= width_sel ? tx_data[15] : tx_data[7];
end
        end

        TRANSFER: begin
  if (!cpha) begin
    if ((sclk_rising && !cpol) || (sclk_falling && cpol)) begin
      shift_rx <= {shift_rx[14:0], miso};
    end
    if ((sclk_falling && !cpol) || (sclk_rising && cpol)) begin
      shift_tx <= {shift_tx[14:0], 1'b0};
      mosi     <= shift_tx[14];
      if (bit_cnt == total_bits - 1)
        state <= DONE;
      else
        bit_cnt <= bit_cnt + 1;
    end
  end
  else begin
    if ((sclk_falling && !cpol) || (sclk_rising && cpol)) begin
      shift_rx <= {shift_rx[14:0], miso};
    end
    if ((sclk_rising && !cpol) || (sclk_falling && cpol)) begin
      shift_tx <= {shift_tx[14:0], 1'b0};
      mosi     <= shift_tx[14];
      if (bit_cnt == total_bits - 1)
        state <= DONE;
      else
        bit_cnt <= bit_cnt + 1;
    end
  end
end

        DONE: begin
          cs_n    <= 1'b1;
          busy    <= 1'b0;
          done    <= 1'b1;
          rx_data <= width_sel ? shift_rx : {8'h0, shift_rx[7:0]};
          state   <= IDLE;
        end

      endcase
    end
  end

endmodule

module spi_slave #(
  parameter DATA_WIDTH = 16
)(
  input  logic        clk,       // system clock (for sync sampling)
  input  logic        rst_n,

  // Config - must match master
  input  logic        cpol,
  input  logic        cpha,
  input  logic        width_sel, // 0 = 8-bit, 1 = 16-bit

  // Data
  input  logic [15:0] tx_data,   // data slave wants to send back
  output logic [15:0] rx_data,   // data received from master
  output logic        done,      // asserted for 1 cycle when transfer complete
  output logic        busy,

  // SPI bus (slave side)
  input  logic        sclk,
  input  logic        cs_n,
  input  logic        mosi,
  output logic        miso
);

  
  // Internal signals
 
  typedef enum logic [1:0] {IDLE, TRANSFER, DONE} state_t;
  state_t state;

  logic [4:0]  bit_cnt;
  logic [4:0]  total_bits;
  logic [15:0] shift_tx;
  logic [15:0] shift_rx;

  
  logic sclk_r1, sclk_r2;

  assign total_bits = width_sel ? 5'd16 : 5'd8;

 
  // Double-flop SCLK synchroniser (metastability protection)
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sclk_r1 <= 1'b0;
      sclk_r2 <= 1'b0;
    end else begin
      sclk_r1 <= sclk;
      sclk_r2 <= sclk_r1;
    end
  end

  wire sclk_rising  = ( sclk_r1 && !sclk_r2);
  wire sclk_falling = (!sclk_r1 &&  sclk_r2);

  
  // MISO drive - always output MSB of shift_tx
  
  assign miso = shift_tx[15];

 
  // Main FSM
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= IDLE;
      bit_cnt  <= '0;
      shift_tx <= '0;
      shift_rx <= '0;
      rx_data  <= '0;
      done     <= 1'b0;
      busy     <= 1'b0;
    end
    else begin
      done <= 1'b0; // default

      case (state)

    
        IDLE: begin
          busy <= 1'b0;
          if (!cs_n) begin
    shift_tx <= width_sel ? tx_data : {tx_data[7:0], 8'h00};
    bit_cnt  <= '0;
    busy     <= 1'b1;
    state    <= TRANSFER;
end
        end

        
        TRANSFER: begin
  if (!cpha) begin
    if ((sclk_rising && !cpol) || (sclk_falling && cpol)) begin
      shift_rx <= {shift_rx[14:0], mosi};
    end
    if ((sclk_falling && !cpol) || (sclk_rising && cpol)) begin
      shift_tx <= {shift_tx[14:0], 1'b0};
      if (bit_cnt == total_bits - 1)
        state <= DONE;
      else
        bit_cnt <= bit_cnt + 1;
    end
  end
  else begin
    if ((sclk_rising && !cpol) || (sclk_falling && cpol)) begin
      shift_tx <= {shift_tx[14:0], 1'b0};
      if (bit_cnt == total_bits - 1)
        state <= DONE;
      else
        bit_cnt <= bit_cnt + 1;
    end
    if ((sclk_falling && !cpol) || (sclk_rising && cpol)) begin
      shift_rx <= {shift_rx[14:0], mosi};
    end
  end
end

        
        DONE: begin
          busy    <= 1'b0;
          done    <= 1'b1;
          rx_data <= width_sel ? shift_rx : {8'h0, shift_rx[7:0]};
          state   <= IDLE;
        end

      endcase
    end
  end

endmodule
