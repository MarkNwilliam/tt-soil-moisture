// moisture_filter.sv — rolling median-of-3 filter
// Presents the median of {new sample, previous two} on each reading once >=3 seen.
module moisture_filter (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] moisture,      // new reading
    input  wire       sample_valid,  // strobe
    output reg  [7:0] median,        // median of last 3
    output reg        valid_out      // pulses when this reading completes a >=3 window
);

    reg [7:0] v1, v2;
    reg [1:0] cnt;

    // Median of (moisture, v1, v2): sum - max - min.
    wire [7:0] mx = (moisture > v1) ? ((moisture > v2) ? moisture : v2)
                                    : ((v1 > v2) ? v1 : v2);
    wire [7:0] mn = (moisture < v1) ? ((moisture < v2) ? moisture : v2)
                                    : ((v1 < v2) ? v1 : v2);
    wire [9:0] sum  = {2'b0, moisture} + {2'b0, v1} + {2'b0, v2};
    wire [9:0] med10 = sum - {2'b0, mx} - {2'b0, mn};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1  <= 8'd0;
            v2  <= 8'd0;
            cnt <= 2'd0;
            median   <= 8'd0;
            valid_out <= 1'b0;
        end else if (sample_valid) begin
            v2 <= v1;
            v1 <= moisture;
            if (cnt != 2'd3)
                cnt <= cnt + 2'd1;
            if (cnt > 2'd1) begin
                median    <= med10[7:0];
                valid_out <= 1'b1;
            end else begin
                median    <= med10[7:0];
                valid_out <= 1'b0;
            end
        end else begin
            valid_out <= 1'b0;
        end
    end
endmodule