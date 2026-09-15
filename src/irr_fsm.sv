// irr_fsm.sv — irrigation controller core
// Decides valve command from filtered moisture, hysteresis, window gating,
// and a fixed sample cadence. Relay timing/protection lives in relay_ctrl.
module irr_fsm (
    input  wire       clk,
    input  wire       rst_n,
    // environment
    input  wire       in_win_any,      // inside either irrigation window
    input  wire       battery_crit,
    input  wire       sw_en_eff,       // manual enable AND cfg enable
    input  wire       f_min_tick,      // one pulse per RTC minute
    // sampling inputs
    input  wire       sensor_valid,    // async ADC strobe (IRQ path)
    // filter link
    output wire       f_sample,        // strobes moisture_filter
    input  wire [7:0] f_median,
    input  wire       f_valid,
    // thresholds / config
    input  wire [7:0] dry_low,
    input  wire [7:0] wet_high,
    input  wire [7:0] sample_min,
    input  wire       sens_irq_en,
    // control
    output reg        valve_cmd
);

    reg        prev_win;
    reg [7:0]  mincnt;
    reg        sample_event;

    wire window_edge = in_win_any && !prev_win;

    // Sample sources: (a) cadence every sample_min minutes, (b) sensor IRQ,
    // (c) window edge. IRQ and window-edge priority over cadence.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_win <= 1'b0;
            mincnt   <= 8'd0;
            sample_event <= 1'b0;
        end else begin
            prev_win <= in_win_any;
            if (sens_irq_en && sensor_valid) begin
                sample_event <= 1'b1;
            end else if (window_edge && sw_en_eff && !battery_crit) begin
                sample_event <= 1'b1;
            end else if (f_min_tick) begin
                if (mincnt >= sample_min - 1) begin
                    mincnt        <= 8'd0;
                    sample_event  <= 1'b1;
                end else begin
                    mincnt        <= mincnt + 8'd1;
                    sample_event  <= 1'b0;
                end
            end else begin
                sample_event <= 1'b0;
            end
        end
    end

    assign f_sample = sample_event;

    // Decision on each completed filter output. Hysteresis := keep last command
    // in the band between dry_low and wet_high.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valve_cmd <= 1'b0;
        else if (f_valid) begin
            if (!sw_en_eff || battery_crit) begin
                valve_cmd <= 1'b0;
            end else if (in_win_any) begin
                if (f_median <= dry_low)
                    valve_cmd <= 1'b1;
                else if (f_median >= wet_high)
                    valve_cmd <= 1'b0;
                // else: maintain prior command (hysteresis band)
            end else begin
                valve_cmd <= 1'b0;
            end
        end
    end
endmodule