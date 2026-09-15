// relay_ctrl.sv — relay drive with min/max on-time enforcement
// Produces a glitch-free valve output and a latched fault on max-on-time overrun.
module relay_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       valve_cmd,     // from irr_fsm
    input  wire       force_off,     // battery_crit | !sw_en_eff  (hard override)
    input  wire       tick_min,      // per-minute pulse from RTC
    input  wire [7:0] min_on,        // minutes held on at minimum
    input  wire [7:0] max_on,        // minutes before fault latch
    input  wire       flt_clear,     // clear fault latch (level)
    output reg        valve,         // final drive, glitch-free
    output reg        fault,
    output reg  [1:0] led_state
);

    localparam [1:0] LED_IDLE    = 2'd0;
    localparam [1:0] LED_ACTIVE  = 2'd1;
    localparam [1:0] LED_FAULT   = 2'd2;
    localparam [1:0] LED_LOWBAT  = 2'd3;

    reg [7:0] on_min_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valve     <= 1'b0;
            fault     <= 1'b0;
            on_min_cnt <= 8'd0;
            led_state <= LED_IDLE;
        end else begin
            if (flt_clear)
                fault <= 1'b0;

            if (force_off) begin
                // Hard override wins over everything, including min-on hold.
                valve      <= 1'b0;
                on_min_cnt <= 8'd0;
            end else if (fault) begin
                // Stuck relay stays off until fault is cleared.
                valve <= 1'b0;
            end else if (valve) begin
                // Currently on: advance on-time counters on minute boundaries.
                if (tick_min) begin
                    on_min_cnt <= on_min_cnt + 8'd1;
                    if (on_min_cnt + 8'd1 >= max_on) begin
                        valve <= 1'b0;
                        fault <= 1'b1;
                        on_min_cnt <= 8'd0;
                    end else if (on_min_cnt + 8'd1 >= min_on) begin
                        // minimum pulse served: follow the command line now
                        valve <= valve_cmd;
                    end
                end else if (!valve_cmd && min_on == 8'd0) begin
                    // min_on=0: drop immediately when command line falls
                    valve <= 1'b0;
                end
                // else: no minute tick, remain on (holds min-on across cmd drops)
            end else begin
                // Off: start a new pulse on request.
                on_min_cnt <= 8'd0;
                valve      <= valve_cmd;
            end

            // Status LED
            if (fault)
                led_state <= LED_FAULT;
            else if (force_off)
                led_state <= LED_LOWBAT;
            else if (valve)
                led_state <= LED_ACTIVE;
            else
                led_state <= LED_IDLE;
        end
    end
endmodule