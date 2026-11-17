// TRANSACTION

class transaction;
  randc bit [15:0] master_tx_data;
  randc bit [15:0] slave_tx_data;
  rand  bit        cpol;
  rand  bit        cpha;
  rand  bit        width_sel;

 
  bit [15:0] master_rx_data;
  bit [15:0] slave_rx_data;

  function void display(string tag = "");
    $display("[%s] cpol=%0d cpha=%0d width=%0d | master_tx=%04h slave_tx=%04h | master_rx=%04h slave_rx=%04h",
             tag, cpol, cpha, width_sel,
             master_tx_data, slave_tx_data,
             master_rx_data, slave_rx_data);
  endfunction

  function transaction copy();
    copy                = new();
    copy.master_tx_data = this.master_tx_data;
    copy.slave_tx_data  = this.slave_tx_data;
    copy.cpol           = this.cpol;
    copy.cpha           = this.cpha;
    copy.width_sel      = this.width_sel;
  endfunction
endclass


// GENERATOR

class generator;
  transaction            trans;
  mailbox #(transaction) mbx;
  event                  done;
  int                    count;

  function new(mailbox #(transaction) mbx, int count = 20);
    trans      = new();
    this.mbx   = mbx;
    this.count = count;
  endfunction

  task run();
    repeat(count) begin
      assert(trans.randomize()) else $error("Randomize failed");
      mbx.put(trans.copy());
      trans.display("GEN");
    end
    -> done;
  endtask
endclass


// INTERFACE

interface spi_if;
  logic        clk;
  logic        rst_n;
  logic        cpol;
  logic        cpha;
  logic        width_sel;
  logic        start;
  logic        done_master;
  logic        busy_master;
  logic        done_slave;
  logic        busy_slave;
  logic [15:0] master_tx_data;
  logic [15:0] slave_tx_data;
  logic [15:0] master_rx_data;
  logic [15:0] slave_rx_data;
endinterface


// DRIVER

class driver;
  transaction            data;
  virtual spi_if         vif;
  mailbox #(transaction) mbx;

  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction

  task run();
   
    vif.rst_n          = 0;
    vif.start          = 0;
    vif.master_tx_data = 0;
    vif.slave_tx_data  = 0;
    vif.cpol           = 0;
    vif.cpha           = 0;
    vif.width_sel      = 0;

  
    repeat(5) @(posedge vif.clk);
    vif.rst_n = 1;
    @(posedge vif.clk);

    forever begin
      mbx.get(data);

      
      @(posedge vif.clk);
      vif.cpol           = data.cpol;
      vif.cpha           = data.cpha;
      vif.width_sel      = data.width_sel;
      vif.master_tx_data = data.master_tx_data;
      vif.slave_tx_data  = data.slave_tx_data;

 
      vif.start = 1;
      @(posedge vif.clk);
      vif.start = 0;

      
      @(posedge vif.clk iff vif.done_master);

     
      @(posedge vif.clk);

      data.display("DRV");
    end
  endtask
endclass


// MONITOR

class monitor;
  transaction            trans;
  virtual spi_if         vif;
  mailbox #(transaction) mbx;

  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction

  task run();
    forever begin

      @(posedge vif.clk iff vif.done_master);

      
      @(posedge vif.clk);

      trans                = new();
      trans.cpol           = vif.cpol;
      trans.cpha           = vif.cpha;
      trans.width_sel      = vif.width_sel;
      trans.master_tx_data = vif.master_tx_data;
      trans.slave_tx_data  = vif.slave_tx_data;
      trans.master_rx_data = vif.master_rx_data; 
      trans.slave_rx_data  = vif.slave_rx_data;  

      trans.display("MON");
      mbx.put(trans);
    end
  endtask
endclass


// SCOREBOARD

class scoreboard;
  mailbox #(transaction) mbx;
  int pass_count;
  int fail_count;
  int total_expected;

  function new(mailbox #(transaction) mbx, int total);
    this.mbx    = mbx;
    this.total_expected = total;
    pass_count  = 0;
    fail_count  = 0;
  endfunction

  task run();
    transaction trans;
    repeat(total_expected) begin
      mbx.get(trans);
      check(trans);
    end
  endtask

  function void check(transaction t);
    bit ok = 1;

    if (t.width_sel == 0) begin
     
      if (t.slave_rx_data !== {8'h00, t.master_tx_data[7:0]}) begin
        $error("[SCB FAIL] 8-bit slave_rx=%04h expected=%04h | cpol=%0d cpha=%0d",
               t.slave_rx_data, {8'h00, t.master_tx_data[7:0]}, t.cpol, t.cpha);
        ok = 0;
      end
      if (t.master_rx_data !== {8'h00, t.slave_tx_data[7:0]}) begin
        $error("[SCB FAIL] 8-bit master_rx=%04h expected=%04h | cpol=%0d cpha=%0d",
               t.master_rx_data, {8'h00, t.slave_tx_data[7:0]}, t.cpol, t.cpha);
        ok = 0;
      end
    end
    else begin
      
      if (t.slave_rx_data !== t.master_tx_data) begin
        $error("[SCB FAIL] 16-bit slave_rx=%04h expected=%04h | cpol=%0d cpha=%0d",
               t.slave_rx_data, t.master_tx_data, t.cpol, t.cpha);
        ok = 0;
      end
      if (t.master_rx_data !== t.slave_tx_data) begin
        $error("[SCB FAIL] 16-bit master_rx=%04h expected=%04h | cpol=%0d cpha=%0d",
               t.master_rx_data, t.slave_tx_data, t.cpol, t.cpha);
        ok = 0;
      end
    end

    if (ok) begin
      $display("[SCB PASS] cpol=%0d cpha=%0d width=%0d | master_tx=%04h->slave_rx=%04h | slave_tx=%04h->master_rx=%04h",
               t.cpol, t.cpha, t.width_sel,
               t.master_tx_data, t.slave_rx_data,
               t.slave_tx_data,  t.master_rx_data);
      pass_count++;
    end
    else begin
      fail_count++;
    end
  endfunction

  function void report();
    
    $display("        SCOREBOARD FINAL REPORT         ");
    $display("  PASS : %0d", pass_count);
    $display("  FAIL : %0d", fail_count);
    $display("  TOTAL: %0d", pass_count + fail_count);
    if (fail_count == 0)
      $display("  STATUS: ALL TESTS PASSED");
    else
      $display("  STATUS: FAILURES DETECTED");
    
  endfunction
endclass


// TESTBENCH TOP

module tb;
  generator  gen;
  driver     drv;
  monitor    mon;
  scoreboard scb;

  spi_if p();

  mailbox #(transaction) gen_drv_mbx;
  mailbox #(transaction) mon_scb_mbx;

  event gen_done;

  spi_top dut (
    .clk            (p.clk),
    .rst_n          (p.rst_n),
    .cpol           (p.cpol),
    .cpha           (p.cpha),
    .width_sel      (p.width_sel),
    .start          (p.start),
    .done_master    (p.done_master),
    .busy_master    (p.busy_master),
    .master_tx_data (p.master_tx_data),
    .slave_rx_data  (p.slave_rx_data),
    .slave_tx_data  (p.slave_tx_data),
    .master_rx_data (p.master_rx_data),
    .done_slave     (p.done_slave),
    .busy_slave     (p.busy_slave)
  );

  
  initial p.clk = 0;
  always #10 p.clk = ~p.clk;

  initial begin
    gen_drv_mbx = new();
    mon_scb_mbx = new();

    gen         = new(gen_drv_mbx, 20);
    drv         = new(gen_drv_mbx);
    mon         = new(mon_scb_mbx);
    scb         = new(mon_scb_mbx, 20);

    drv.vif     = p;
    mon.vif     = p;

    gen_done    = gen.done;
  end

  initial begin
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
    join_none;

    wait(scb.pass_count + scb.fail_count == 20);

    
    repeat(5000) @(posedge p.clk);

    scb.report();
    $finish();
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
endmodule
