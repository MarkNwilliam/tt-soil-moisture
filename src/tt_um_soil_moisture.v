/*
 * tt_um_soil_moisture — Tiny Tapeout wrapper for the low-power soil-moisture
 * irrigation controller (IC Projects/2-Soil-Moisture-Irrigation-ASIC).
 *
 * The controller core is configured through the UIO pins using a 24-bit
 * LSB-first serial frame shifted in on `mosi` while `cs_n` is low, one bit
 * per clock (the chip clock doubles as the SPI clock):
 *
 *     bit  0     = start  (must be 1)   -> shift[23]
 *     bit  1     = rw     (1 = write)   -> shift[22]
 *     bits 5:2   = paddr[3:0]           -> shift[21:18]
 *     bits 21:6  = pwdata[15:0]         -> shift[17:2]
 *     bits 23:22 = 0 (pad)              -> shift[1:0]
 *
 * Pin map:
 *   ui_in[7:0]  = moisture[7:0]      raw ADC reading
 *   uio[0]      = (reserved, unused)
 *   uio[1]      = cs_n               active-low chip select (in)
 *   uio[2]      = mosi               serial data in (in)
 *   uio[3]      = sw_en              manual enable (in)
 *   uio[4]      = sensor_valid       ADC strobe / IRQ (in)
 *   uio[5]      = battery_crit       low-battery warning (in)
 *   uo_out[0]   = valve
 *   uo_out[1:2] = led_state[1:0]
 *   uo_out[3]   = fault
 *   uo_out[4]   = battery_crit (echo)
 *   uo_out[5]   = sensor_valid (echo)
 *   uo_out[6]   = 0 (reserved)
 *   uo_out[7]   = sw_en (echo)
 *
 * Registers (APB-Lite, 16-bit):
 *   0x0 CFG      [0] EN [1] SENS_IRQ [4] FLT_CLEAR [5] LED_EN
 *   0x1 DRY_LOW  [7:0]
 *   0x2 WET_HIGH [7:0]
 *   0x3 WINDOW1  [15:8] end, [7:0] start
 *   0x4 WINDOW2  [15:8] end, [7:0] start
 *   0x5 ONTIME   [15:8] max_on, [7:0] min_on
 *   0x6 SAMPRATE [7:0]
 *   0x7 TIME     [15:8] hour, [7:0] minute  (write = set time)
 */

`default_nettype none

module tt_um_soil_moisture #(
    parameter TICKS_PER_SEC = 32768
) (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // ---- serial (write-only) config framing ----
  // SPI clock == chip clock. mosi sampled on every posedge while cs_n low.
  wire cs_n_i = uio_in[1];
  wire mosi_i = uio_in[2];

  reg [23:0] shift;
  reg [4:0] nbits;
  reg frame_d;

  // SPI clock = chip clock. mosi is sampled on every posedge while cs_n is low.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      shift  <= 24'd0;
      nbits  <= 5'd0;
    end else begin
      if (cs_n_i) begin
        shift <= 24'd0;
        nbits <= 5'd0;
      end else if (nbits != 5'd24) begin
        shift <= {shift[22:0], mosi_i};
        nbits <= nbits + 5'd1;
      end
    end
  end

  // shift contains the frame MSB-aligned; reconstruct the transmit-order word
  wire [23:0] fw;
  genvar g;
  generate
    for (g = 0; g < 24; g = g + 1) assign fw[g] = shift[23 - g];
  endgenerate

  wire frame_valid = !cs_n_i && (nbits == 5'd24) && fw[0];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      frame_d <= 1'b0;
    else
      frame_d <= frame_valid;
  end

  wire frame_rise  = frame_valid && !frame_d;
  wire apb_wr      = frame_rise && fw[1];
  wire [3:0]  apb_addr  = fw[5:2];
  wire [15:0] apb_wdata = fw[21:6];

  // ---- controller core I/O ----
  wire        valve;
  wire [1:0]  led_state;
  wire        fault;
  wire        sw_en       = uio_in[3];
  wire        sensor_valid = uio_in[4];
  wire        battery_crit = uio_in[5];
  wire [15:0] prdata;

  // ---- controller core (32.768 kHz RTC time base) ----
  top #(.TICKS_PER_SEC(TICKS_PER_SEC)) u_core (
    .clk_32k     (clk),
    .rst_n       (rst_n),
    .moisture    (ui_in),
    .sensor_valid(sensor_valid),
    .battery_crit(battery_crit),
    .sw_en       (sw_en),
    .valve       (valve),
    .led_state   (led_state),
    .fault       (fault),
    .paddr       (apb_addr),
    .psel        (apb_wr),
    .penable     (apb_wr),
    .pwrite      (apb_wr),
    .pwdata      (apb_wdata),
    .prdata      (prdata)
  );

  // ---- outputs ----
  assign uo_out[0] = valve;
  assign uo_out[1] = led_state[0];
  assign uo_out[2] = led_state[1];
  assign uo_out[3] = fault;
  assign uo_out[4] = battery_crit;
  assign uo_out[5] = sensor_valid;
  assign uo_out[6] = 1'b0;
  assign uo_out[7] = sw_en;

  assign uio_out = 8'd0;
  assign uio_oe  = 8'd0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, uio_in[0], uio_in[6], uio_in[7], prdata, 1'b0};

endmodule