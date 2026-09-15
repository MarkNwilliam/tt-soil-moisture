// rtc_timer.sv — always-on 32 kHz time base
// Produces seconds/minutes/hours, per-minute ticks, and irrigation window flags.
module rtc_timer #(
    parameter TICKS_PER_SEC = 32768   // override small in simulation
) (
    input  wire       clk_32k,
    input  wire       rst_n,
    // config
    input  wire [7:0] win1_start,
    input  wire [7:0] win1_end,
    input  wire [7:0] win2_start,
    input  wire [7:0] win2_end,
    // time set
    input  wire [7:0] load_hour,
    input  wire [7:0] load_minute,
    input  wire       ld_time,
    // outputs
    output reg  [7:0] hour,
    output reg  [7:0] minute,
    output reg  [7:0] seconds,
    output wire       tick_sec,
    output wire       tick_min,
    output wire       in_win1,
    output wire       in_win2
);

    reg [31:0] tick;
    wire       tick_done = (tick >= TICKS_PER_SEC - 1);

    always @(posedge clk_32k or negedge rst_n) begin
        if (!rst_n) begin
            tick    <= 0;
            seconds <= 0;
            minute  <= 0;
            hour    <= 0;
        end else if (ld_time) begin
            tick    <= 0;
            seconds <= 0;
            minute  <= load_minute[5:0];
            hour    <= load_hour[4:0];
        end else begin
            if (tick_done) begin
                tick <= 0;
                if (seconds == 59) begin
                    seconds <= 0;
                    if (minute == 59) begin
                        minute <= 0;
                        if (hour == 23)
                            hour <= 0;
                        else
                            hour <= hour + 1;
                    end else begin
                        minute <= minute + 1;
                    end
                end else begin
                    seconds <= seconds + 1;
                end
            end else begin
                tick <= tick + 1;
            end
        end
    end

    assign tick_sec = tick_done;
    // pulse on the minute boundary (seconds wrapping to 0)
    assign tick_min = tick_done & (seconds == 59);

    assign in_win1 = win1_end > win1_start ? (hour >= win1_start[4:0]) && (hour < win1_end[4:0]) : 1'b0;
    assign in_win2 = win2_end > win2_start ? (hour >= win2_start[4:0]) && (hour < win2_end[4:0]) : 1'b0;
endmodule