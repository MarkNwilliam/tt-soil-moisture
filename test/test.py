# SPDX-FileCopyrightText: (c) 2026 Mark Nkugwa
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge


# ---- uio_in bit map ----
UO_SCLK    = 0x01   # uio[0]
UO_CS_N    = 0x02   # uio[1]
UO_MOSI    = 0x04   # uio[2]
UO_SW_EN   = 0x08   # uio[3]
UO_SENS_V  = 0x10   # uio[4]
UO_BAT_CRIT= 0x20   # uio[5]


async def shift_frame(dut, addr, data, uio_base):
    """Shift a 24-bit write frame LSB-first via cs_n/mosi, one bit per clock.
       Frame: {pad[23:22], data[21:6], addr[5:2], rw[1], start[0]}.
       mosi/cs_n are driven at the falling edge so they are stable at the
       chip posedge that samples them."""
    uio_core  = uio_base & ~0x07                # sclk=0, cs=0, mosi=0
    cs_n_hi   = uio_core | UO_CS_N               # cs deasserted
    cs_n_lo   = uio_core                          # cs asserted

    fv = (1                      # start
          | (1 << 1)             # rw = write
          | ((addr & 0xF) << 2)  # paddr
          | ((data & 0xFFFF) << 6))  # pwdata

    # Deassert cs across a full posedge so shift/nbits are cleared
    dut.uio_in.value = cs_n_hi
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)

    # Shift 24 bits, one per posedge while cs stays low
    for i in range(24):
        bit = (fv >> i) & 1
        dut.uio_in.value = cs_n_lo | (bit << 2)
        await RisingEdge(dut.clk)            # design samples mosi here
        await FallingEdge(dut.clk)           # settle before next bit

    # Write strobe fires on the posedge after the last captured bit
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.uio_in.value = cs_n_hi
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)


async def sample(dut, moisture_val, uio_base):
    """Pulse sensor_valid for 2 clocks with the given moisture reading."""
    dut.ui_in.value = moisture_val
    dut.uio_in.value = uio_base | UO_SENS_V
    await ClockCycles(dut.clk, 2)
    dut.uio_in.value = uio_base
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start — tt_um_soil_moisture functional test")

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # ---- reset ----
    dut.ena.value   = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 3)

    # After reset: cfg_en=1, sens_irq_en=1, led_en=1, dry_low=60, wet_high=170
    # Window1 default 0x1800 → always in window. Valve should be OFF.
    assert (int(dut.uo_out.value) & 1) == 0, "valve should be OFF after reset"
    assert ((int(dut.uo_out.value) >> 3) & 1) == 0, "fault should be OFF after reset"
    dut._log.info("Reset defaults OK")

    # ---- setup: sw_en=1, cs_n=1 (idle) ----
    uio = UO_CS_N | UO_SW_EN                # cs_n=1, sw_en=1
    dut.uio_in.value = uio
    await ClockCycles(dut.clk, 2)

    # ---- write DRY_LOW=200 (0xC8) and WET_HIGH=170 (0xAA) ----
    await shift_frame(dut, 0x1, 0x00C8, uio)
    await shift_frame(dut, 0x2, 0x00AA, uio)
    dut._log.info("Wrote DRY_LOW=200, WET_HIGH=170")

    # ---- feed 3x dry (moisture=100 <= DRY_LOW=200) → valve should turn ON.
    #      Note: default dry_low=60, so 100 only irrigates if the write took. ----
    dut._log.info("Feeding 3x dry samples (moisture=100 <= DRY_LOW=200)")
    for i in range(3):
        await sample(dut, 100, uio)

    await ClockCycles(dut.clk, 10)

    valve = int(dut.uo_out.value) & 1
    led   = (int(dut.uo_out.value) >> 1) & 0x3
    dut._log.info(f"valve={valve}  led_state={led}")
    assert valve == 1,  "valve should be ON (dry soil)"
    assert led == 0x1,  "led_state should be ACTIVE (0b01)"

    # ---- battery_crit → force off + LED LOWBAT ----
    dut._log.info("Asserting battery_crit")
    dut.uio_in.value = uio | UO_BAT_CRIT
    await ClockCycles(dut.clk, 5)
    assert (int(dut.uo_out.value) & 1) == 0, "valve OFF under battery_crit"
    led_after = (int(dut.uo_out.value) >> 1) & 0x3
    dut._log.info(f"led_state under battery_crit={led_after}")
    assert led_after == 0x3, "led should be LOWBAT (0b11)"

    # Release battery_crit
    dut.uio_in.value = uio
    await ClockCycles(dut.clk, 5)

    # Feed dry samples again to re-arm
    dut._log.info("Re-sampling after battery_crit release")
    for _ in range(3):
        await sample(dut, 50, uio)
    await ClockCycles(dut.clk, 10)
    assert (int(dut.uo_out.value) & 1) == 1, "valve should recover"
    dut._log.info("Valve recovered")

    # ---- fault test: set max_on=2 (ONTIME=0x0201 → min_on=1,max_on=2) ----
    dut._log.info("Writing ONTIME=0x0201 (max_on=2 min_on=1)")
    await shift_frame(dut, 0x5, 0x0201, uio)

    # Wait 2 minute ticks (TICKS_PER_SEC=4 → 1 min=240 clks → 2 min=480 clks + margin)
    dut._log.info("Waiting ~500 clocks for 2 minute ticks to trigger fault")
    await ClockCycles(dut.clk, 520)
    fault = (int(dut.uo_out.value) >> 3) & 1
    dut._log.info(f"fault after 2+ min = {fault}")
    assert fault == 1, "fault should latch after max_on exceeded"
    assert (int(dut.uo_out.value) & 1) == 0, "valve should be OFF during fault"

    # ---- clear fault (write CFG bit4=1) then re-enable ----
    dut._log.info("Clearing fault via CFG FLT_CLEAR (0x10)")
    await shift_frame(dut, 0x0, 0x0010, uio)
    await ClockCycles(dut.clk, 3)
    assert ((int(dut.uo_out.value) >> 3) & 1) == 0, "fault cleared"

    # Re-enable config: en=1, irq=1, led_en=1  → 0x0027
    await shift_frame(dut, 0x0, 0x0027, uio)
    await ClockCycles(dut.clk, 2)
    dut._log.info("CFG re-enabled, fault cleared")

    # ---- disable cfg_en → valve off despite dry soil ----
    dut._log.info("Disabling cfg_en (CFG=0x0000)")
    await shift_frame(dut, 0x0, 0x0000, uio)
    for _ in range(3):
        await sample(dut, 50, uio)
    await ClockCycles(dut.clk, 10)
    assert (int(dut.uo_out.value) & 1) == 0, "valve off when cfg_en=0"
    dut._log.info("cfg_en=0 correctly blocks valve")

    # Re-enable
    await shift_frame(dut, 0x0, 0x0027, uio)
    await ClockCycles(dut.clk, 2)
    # Drop min_on so the valve follows valve_cmd instantly in this test:
    # min_on=0, max_on=255 (ONTIME=0xFF00) → no pulse hold, no fault.
    await shift_frame(dut, 0x5, 0xFF00, uio)
    await ClockCycles(dut.clk, 2)

    # ---- out-of-window → valve off ----
    dut._log.info("Setting WINDOW1=0 (disabled)")
    await shift_frame(dut, 0x3, 0x0000, uio)
    await ClockCycles(dut.clk, 2)
    for _ in range(3):
        await sample(dut, 50, uio)
    await ClockCycles(dut.clk, 10)
    assert (int(dut.uo_out.value) & 1) == 0, "valve off outside window"
    dut._log.info("Out-of-window correctly blocks valve")

    # Restore default window (0x1800 = start 0, end 24 → always on)
    await shift_frame(dut, 0x3, 0x1800, uio)
    await ClockCycles(dut.clk, 2)

    # ---- sensor_valid echo on uo_out[5] ----
    dut.ui_in.value = 0
    dut.uio_in.value = uio | UO_SENS_V
    await ClockCycles(dut.clk, 1)
    sv_echo = (int(dut.uo_out.value) >> 5) & 1
    dut._log.info(f"sensor_valid echo = {sv_echo}")
    assert sv_echo == 1, "sensor_valid echo should be 1 when asserted"
    dut.uio_in.value = uio
    await ClockCycles(dut.clk, 1)

    dut._log.info("ALL TESTS PASSED")
