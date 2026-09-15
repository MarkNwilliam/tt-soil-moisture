## How it works

An always-on 32 kHz RTC provides per-minute ticks and two configurable irrigation windows (hour-of-day ranges). A rolling median-of-3 filter smooths the raw 8-bit moisture ADC reading. The FSM samples periodically, on window edges, or on an ADC interrupt, then compares the filtered value against configurable dry/wet thresholds (hysteresis). When the soil is dry and inside an irrigation window, it commands the relay (valve) on. A relay controller enforces configurable minimum and maximum on-time per pulse and latches a fault if the valve runs past max_on.

Configuration and time-setting are done through the UIO pins using a 24-bit serial frame: while `CS_N` (uio[1]) is low, `MOSI` (uio[2]) is sampled on every chip-clock posedge (the chip clock doubles as the serial clock; no separate `SCLK` is needed). The 8-bit status (valve, LED state, fault, battery, sensor valid, sw_en) is continuously visible on uo_out.

## How to test

1. After reset, set `SW_EN` (uio[3]) high.
2. Send serial write frames to set thresholds, e.g. `DRY_LOW=200` via `write_frame(addr=1, data=0xC8)` (24 bits, LSB-first: `{pad[23:22], data[21:6], addr[5:2], rw[1], start[0]}`).
3. Feed three consecutive dry moisture readings via `ui_in[7:0]` + pulse `sensor_valid` (uio[4]) three times. `VALVE` (uo_out[0]) should go high.
4. Assert `BAT_CRIT` (uio[5]) → valve is forced off, LED enters LOWBAT state.
5. Set ONTIME so `max_on` is small and wait enough minute ticks → fault latches. Clear it by writing `FLT_CLEAR` in the CFG register.

## External hardware

Requires an ADC providing an 8-bit moisture reading (directly on `ui_in`) and a host microcontroller bit-banging the 24-bit SPI-like frame on the UIO pins, driving `MOSI` on the falling chip-clock edge so it is stable at the rising edge that samples it. An external relay driver is needed to interface the `VALVE` output to a solenoid.
