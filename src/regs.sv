// regs.sv — APB-Lite register bank (16-bit data path)
// 0x0 CFG     [5:0] EN, SENS_IRQ, PWM_EN, PWM_POL, FLT_CLEAR, LED_EN
// 0x1 DRY_LOW [7:0]
// 0x2 WET_HIGH[7:0]
// 0x3 WINDOW1 [15:8] end, [7:0] start
// 0x4 WINDOW2 [15:8] end, [7:0] start
// 0x5 ONTIME  [15:8] max_on, [7:0] min_on
// 0x6 SAMPRATE[7:0]
// 0x7 TIME    [15:8] hour, [7:0] minute   (write = set, read = current)
// 0x8 STATUS  R       [7] IN_WIN [6] SAMPLE_BUSY [5] FAULT [4] LOWBAT
//                     [3] RELAY_ON [2:1] LED_STATE [0] DONE
module regs (
    input  wire        pclk,
    input  wire        rst_n,
    // APB-Lite slave side
    input  wire [3:0]  paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [15:0] pwdata,
    output reg  [15:0] prdata,
    // status window
    input  wire        in_win,
    input  wire        sample_busy,
    input  wire        relay_on,
    input  wire        fault_in,
    input  wire        force_off,
    input  wire [1:0]  led_state_in,
    // config out
    output reg         cfg_en,
    output reg         sens_irq_en,
    output reg         led_en,
    output reg         flt_clear,
    output reg  [7:0]  dry_low,
    output reg  [7:0]  wet_high,
    output reg  [15:0] window1,
    output reg  [15:0] window2,
    output reg  [15:0] ontime,
    output reg  [7:0]  sample_min,
    // time set / read
    output reg  [7:0]  load_hour,
    output reg  [7:0]  load_minute,
    output reg         ld_time,
    input  wire [7:0]  cur_hour,
    input  wire [7:0]  cur_minute
);

    wire [15:0] rdata;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_en      <= 1'b1;
            sens_irq_en <= 1'b1;
            led_en      <= 1'b1;
            flt_clear   <= 1'b0;
            dry_low     <= 8'd60;
            wet_high    <= 8'd170;
            window1     <= 16'h1800;  // start 0, end 24 -> irrigate all day
            window2     <= 16'h0000;  // start 0, end 0  -> disabled
            ontime      <= 16'h3C01;  // min_on 1, max_on 60
            sample_min  <= 8'd15;
            load_hour   <= 8'd0;
            load_minute <= 8'd0;
            ld_time     <= 1'b0;
        end else if (psel && penable && pwrite) begin
            ld_time <= 1'b0;
            case (paddr)
                4'h0: begin
                    if (pwdata[0]) cfg_en <= 1'b1; else cfg_en <= 1'b0;
                    if (pwdata[1]) sens_irq_en <= 1'b1; else sens_irq_en <= 1'b0;
                    if (pwdata[5]) led_en <= 1'b1; else led_en <= 1'b0;
                    flt_clear <= pwdata[4];
                end
                4'h1: dry_low   <= pwdata[7:0];
                4'h2: wet_high  <= pwdata[7:0];
                4'h3: window1   <= pwdata;
                4'h4: window2   <= pwdata;
                4'h5: ontime    <= pwdata;
                4'h6: sample_min<= pwdata[7:0];
                4'h7: begin
                    load_hour   <= pwdata[15:8];
                    load_minute <= pwdata[7:0];
                    ld_time     <= 1'b1;
                end
                default: ;
            endcase
        end else begin
            flt_clear <= 1'b0;
            ld_time   <= 1'b0;
        end
    end

    assign rdata =
        (paddr == 4'h0) ? {10'd0, led_en, flt_clear, 1'b0, sens_irq_en, cfg_en} :
        (paddr == 4'h1) ? {8'd0, dry_low} :
        (paddr == 4'h2) ? {8'd0, wet_high} :
        (paddr == 4'h3) ? window1 :
        (paddr == 4'h4) ? window2 :
        (paddr == 4'h5) ? ontime :
        (paddr == 4'h6) ? {8'd0, sample_min} :
        (paddr == 4'h7) ? {cur_hour, cur_minute} :
        (paddr == 4'h8) ? {8'd0, in_win, sample_busy, fault_in, force_off, relay_on, led_state_in, 1'b0} :
        16'd0;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n)
            prdata <= 16'd0;
        else if (psel && !pwrite)
            prdata <= rdata;
    end
endmodule