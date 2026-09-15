// top.sv — soil-moisture irrigation controller
// Single 32 kHz domain; APB-Lite config; always-on RTC; gated irrigation core.
module top #(
    parameter TICKS_PER_SEC = 32768
) (
    input  wire       clk_32k,
    input  wire       rst_n,
    // sensor
    input  wire [7:0] moisture,
    input  wire       sensor_valid,
    // environment
    input  wire       battery_crit,
    input  wire       sw_en,
    // outputs
    output wire       valve,
    output wire [1:0] led_state,
    output wire       fault,
    // APB-Lite config bus (pclk = clk_32k)
    input  wire [3:0]  paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [15:0] pwdata,
    output wire [15:0] prdata
);

    // ---- wiring ----
    wire [7:0] hour, minute, seconds;
    wire       tick_sec, tick_min, in_win1, in_win2;
    wire       in_win_any = in_win1 | in_win2;

    wire [7:0] load_hour, load_minute;
    wire       ld_time;

    wire       cfg_en, sens_irq_en, led_en, flt_clear;
    wire [7:0] dry_low, wet_high, sample_min;
    wire [15:0] window1, window2, ontime;
    wire [7:0] min_on  = ontime[7:0];
    wire [7:0] max_on  = ontime[15:8];
    wire [7:0] win1_s  = window1[7:0];
    wire [7:0] win1_e  = window1[15:8];
    wire [7:0] win2_s  = window2[7:0];
    wire [7:0] win2_e  = window2[15:8];

    wire sw_en_eff = sw_en & cfg_en;
    wire force_off = battery_crit | ~sw_en_eff;

    wire       f_sample, f_valid;
    wire [7:0] f_median;

    wire valve_cmd;

    reg  [1:0] led_out;

    wire       sel_fault;
    reg        relay_busy;

    // ---- instances ----
    rtc_timer #(.TICKS_PER_SEC(TICKS_PER_SEC)) u_rtc (
        .clk_32k   (clk_32k),
        .rst_n     (rst_n),
        .win1_start(win1_s),
        .win1_end  (win1_e),
        .win2_start(win2_s),
        .win2_end  (win2_e),
        .load_hour (load_hour),
        .load_minute(load_minute),
        .ld_time   (ld_time),
        .hour      (hour),
        .minute    (minute),
        .seconds   (seconds),
        .tick_sec  (tick_sec),
        .tick_min  (tick_min),
        .in_win1   (in_win1),
        .in_win2   (in_win2)
    );

    moisture_filter u_filter (
        .clk      (clk_32k),
        .rst_n    (rst_n),
        .moisture (moisture),
        .sample_valid(f_sample),
        .median   (f_median),
        .valid_out(f_valid)
    );

    irr_fsm u_fsm (
        .clk         (clk_32k),
        .rst_n       (rst_n),
        .in_win_any  (in_win_any),
        .battery_crit(battery_crit),
        .sw_en_eff   (sw_en_eff),
        .f_min_tick  (tick_min),
        .sensor_valid(sensor_valid),
        .f_sample    (f_sample),
        .f_median    (f_median),
        .f_valid     (f_valid),
        .dry_low     (dry_low),
        .wet_high    (wet_high),
        .sample_min  (sample_min),
        .sens_irq_en (sens_irq_en),
        .valve_cmd   (valve_cmd)
    );

    relay_ctrl u_relay (
        .clk      (clk_32k),
        .rst_n    (rst_n),
        .valve_cmd(valve_cmd),
        .force_off(force_off),
        .tick_min (tick_min),
        .min_on   (min_on),
        .max_on   (max_on),
        .flt_clear(flt_clear),
        .valve    (valve),
        .fault    (sel_fault),
        .led_state(led_out)
    );

    regs u_regs (
        .pclk        (clk_32k),
        .rst_n       (rst_n),
        .paddr       (paddr),
        .psel        (psel),
        .penable     (penable),
        .pwrite      (pwrite),
        .pwdata      (pwdata),
        .prdata      (prdata),
        .in_win      (in_win_any),
        .sample_busy (relay_busy),
        .relay_on    (valve),
        .fault_in    (sel_fault),
        .force_off   (force_off),
        .led_state_in(led_out),
        .cfg_en      (cfg_en),
        .sens_irq_en (sens_irq_en),
        .led_en      (led_en),
        .flt_clear   (flt_clear),
        .dry_low     (dry_low),
        .wet_high    (wet_high),
        .window1     (window1),
        .window2     (window2),
        .ontime      (ontime),
        .sample_min  (sample_min),
        .load_hour   (load_hour),
        .load_minute (load_minute),
        .ld_time     (ld_time),
        .cur_hour    (hour),
        .cur_minute  (minute)
    );

    // Busy status = filter round in flight (stroked but not yet decided)
    always @(posedge clk_32k or negedge rst_n)
        if (!rst_n)
            relay_busy <= 1'b0;
        else
            relay_busy <= f_sample ? 1'b1 : (f_valid ? 1'b0 : relay_busy);

    // LED export (gated by LED_EN)
    assign led_state = led_en ? led_out : 2'd0;
    assign fault     = sel_fault;
endmodule