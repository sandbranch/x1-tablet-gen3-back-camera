# Rear camera — ThinkPad X1 Tablet Gen 3

The rear camera (OV8858 behind a TPS68470 PMIC, on Intel IPU3) does not work on Linux.
These patches get the sensor detected and the pipeline connected. **It still does not
stream** — the remaining fault is characterised below.

Tested on Ubuntu 26.04, kernel 7.0.0-29-generic. **Two of the three patches have since
been merged upstream by someone else — see [Upstream status](#upstream-status) before
applying anything here.**

## Status

| | |
|---|---|
| Sensor detected over I²C | ✅ `ov8858: Detected OV8858 sensor, revision 0xb2` |
| IPU3 pipeline connected | ✅ `ipu3-cio2: Connected 1 cameras` |
| Streaming | ❌ sensor stops answering ~20–40 ms after power-on |

## What the patches fix

**`0001-int3472-board-data.patch`** — adds board data for this machine, and opens the
PMIC's I²C passthrough. `S_I2C_CTL` boots at `0x00`; the sensor sits behind it and is
unreachable until it is set to `0x03`. This is the change that first produced a chip ID.

**`0002-ov8858-acpi-match-int3477.patch`** — adds the `INT3477` ACPI match, and adds
`vsio` to the sensor's supply list so the driver holds the TPS68470 regulator that gates
I²C passthrough.

> **Correction.** An earlier version of this file said this patch "sets `xvclk` to 24 MHz
> in `ov8858_power_on()`". It does not, and no patch here does. The clock running at
> 19.2 MHz where every ov8858 register table assumes 24 MHz is a real *observation* from
> this machine — upstream only warns about it (`ov8858.c`, "xvclk mismatched, modes are
> based on 24MHz") — but it was never turned into a change in this repository. Treat it
> as an open lead, not as something these patches fix. Related: `0001` below configures
> five regulators and the GPIOs but **no clock consumers**, unlike the mainline Surface Go
> and Latitude 5285 board data, which is a plausible cause worth investigating.

**`0003-ipu-bridge-int3477.patch`** — adds `INT3477` to the ipu-bridge sensor table, so
the sensor is bridged to cio2.

The camera is module `CJAG829` at I²C `0x36` on `\_SB.PCI0.LNK0`, ACPI HID **`INT3477`**.
It is *not* `CAM0` / `INT3471` at `0x10` — that is a stale Intel reference-design stub for
an IMX135 this machine does not have, and no amount of DSDT work makes it respond.

## Applying

```bash
git clone --depth 1 -b v7.0 <your kernel tree> && cd linux
git apply /path/to/000*.patch
make -j$(nproc) modules SUBDIRS=drivers/media/i2c drivers/media/pci/intel
sudo make modules_install && sudo update-initramfs -u
sudo reboot
./check-cameras.sh          # what the kernel sees after the reboot
```

## What is still broken

The sensor answers I²C for **20–40 ms after power-on and then goes mute while still
powered**. Measured three independent ways; it is time-based, not traffic-induced, and it
is not the driver powering the part down. That rules out a marginal bus and points at the
`dvdd` / CORE 1.2 V rail: on the TPS68470, `VDCTL` bit 0 refuses to latch while `VACTL`
sets normally.

`pmic-bringup-sequence.txt` is the TPS68470 bring-up sequence captured off the I²C wire
from Lenovo's own Windows driver, including the registers Linux never writes
(`0x41=6D 0x40=34 0x42=0C 0x3C=6D 0x3F=34 0x48=05 0x44=01`, plus a `0x06–0x10` block).
Note it is a *failing* attempt: Windows retries six times and gives up with Code 10, so
the rear camera does not work on Windows either.

Disassembly of the vendor driver confirms our GPIO mapping is already correct
(reset = 9, powerdown = 7, active-low). The only behavioural difference left is ordering —
the vendor releases reset first, then asserts enable, where `ov8858_power_on()` does
powerdown then reset with no gap. Both reach `SGPO=0x05`.

## Notes for anyone testing

- **One attempt per boot.** Reloading `ov8858` permanently severs the sensor→csi2 link
  (`Link has been severed`), and `int3472` probes exactly once per boot.
- **Do not sweep the TPS68470 GPIOs.** Driving `gpio.1`/`gpio.2` high wedges the
  designware I²C controller unrecoverably. Those lines are bus-related, not camera reset.
- A failing manual `i2cget 0x36` is not a regression — `UU` means the driver owns the
  device and it is runtime-suspended.
- Unsigned modules need Secure Boot off, which changes PCR 7. If your root filesystem is
  LUKS with a TPM-bound unlock, that binding breaks and you get a passphrase prompt —
  make sure you know it before rebooting.

## Upstream status

Checked against mainline **7.4.0-rc1** on 2026-11-06. **None of the three patches apply
to a current tree**, and two are redundant:

| patch | status upstream |
|---|---|
| `0003` ipu-bridge `INT3477` | **already merged** — mainline carries `IPU_SENSOR_CONFIG("INT3477", 1, 360000000)` verbatim, same comment and position |
| `0002`, the ACPI match | **already merged** — `ov8858_acpi_ids` with `{ .id = "INT3477" }` and `.acpi_match_table` |
| `0002`, the `vsio` supply | **not merged**, and not in linux-next — but it is in Thierry Chatard's active v10 series, so do not duplicate it |
| `0001` tps68470 board data | **not merged**; no ThinkPad X1 Tablet entry exists upstream. This is the only part of this repository that is still a distinct contribution |

Nothing here has been submitted to the kernel, and there is no plan to. Two of the three
patches were overtaken by Chatard's work on the Latitude 5285, which covers the same
OV8858 + TPS68470 + IPU3 combination; the third is held back by the unresolved clock
question above. Anyone who wants to carry `0001` upstream is welcome to — please do.

## Prior art

Thierry Chatard has the same OV8858 + TPS68470 + IPU3 combination working in libcamera on
a Dell Latitude 5285; his series is on linux-media. Patch `0003` here matched his
equivalent byte-for-byte before either of us had seen the other's work. Two of his five
patches were measured against this machine and do not apply: the LPSS resource-conflict
quirk is not our fault mode, and the INT3472 GNVS clock fields do not match this firmware.

## Licence

Copyright (c) 2026 David Sandquist.

GPL-2.0 — see `LICENSE`. These are patches against GPL-2.0 kernel files, so they
carry the same licence rather than the MIT used by the sibling repositories.
