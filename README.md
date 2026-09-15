![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Soil-Moisture Irrigation ASIC

A low-power soil-moisture irrigation controller for Tiny Tapeout. It reads an 8-bit
soil-moisture ADC, smooths it with a rolling median-of-3 filter, and drives a relay
(valve) when the soil is dry and the current time is inside a configured irrigation
window. Minimum/maximum valve on-time and a latched fault protect against stuck relays.

- [Read the documentation for project](docs/info.md)

## How it works

- An always-on RTC produces per-minute ticks and tracks the time-of-day.
- Two configurable irrigation windows gate irrigation to hours-of-day.
- The FSM samples periodically, on window edges, or on an ADC interrupt, then applies
  dry/wet thresholds with hysteresis.
- `relay_ctrl` enforces `min_on`/`max_on` minutes per pulse and latches `FAULT` on overrun.
- Configuration is written over a 24-bit serial frame on the UIO pins
  (`CS_N`/`MOSI`, sampled on the chip clock); status is continuously visible on `uo_out`.

## How to test

See [docs/info.md](docs/info.md) for the full test procedure. In short: enable `SW_EN`, write
`DRY_LOW`/`WET_HIGH` and time-bases over the serial frame, pulse `SENS_VALID` with a dry
reading, and watch `VALVE` go high. Simulation runs with `make -B` in `test/`
(cocotb + iverilog); the real-time RTC is sped up via `TICKS_PER_SEC`.

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that makes it easier and cheaper than ever to get
your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.