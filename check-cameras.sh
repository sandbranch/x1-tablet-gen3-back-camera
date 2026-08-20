#!/bin/bash
# Search ALL ACPI tables (not just DSDT) for real camera sensor declarations
# and for whoever writes the SCSS gate variable.
set -e
# scratch dir for the table dump; override with WORKDIR=... if you want to keep it
D="${WORKDIR:-$(mktemp -d -t camera-acpi-XXXXXX)}"
mkdir -p "$D/acpi" && cd "$D/acpi"

echo "==> dumping all ACPI tables"
sudo acpidump -b
sudo chown "$USER" ./*.dat 2>/dev/null || true

echo "==> decompiling (errors on cross-table refs are expected/harmless)"
iasl -d ./*.dat >/dev/null 2>&1 || true

echo
echo "=============================================="
echo " Camera sensor names across ALL tables"
echo "=============================================="
grep -nE '"(IMX|OV[0-9]|HI[0-9]{3}|GC[0-9]|S5K|AR[0-9]{4})[^"]*"' ./*.dsl 2>/dev/null | head -20 \
  || echo "(none beyond what we already saw)"

echo
echo "=============================================="
echo " Who WRITES SCSS? (assignment, not comparison)"
echo "=============================================="
grep -nE 'SCSS *=|Store *\(.*, *SCSS' ./*.dsl 2>/dev/null \
  || echo "NOT WRITTEN in any table -> value comes from BIOS/firmware at boot"

echo
echo "=============================================="
echo " All camera Device blocks + their HIDs"
echo "=============================================="
grep -nE 'Device \(CAM[0-9]\)|Device \(LNK[0-9]\)|"INT34[0-9][0-9]"' ./*.dsl 2>/dev/null | head -20

echo
echo "=============================================="
echo " Current SCSS value from live GNVS"
echo "=============================================="
echo "GNVS base 0x5B134000 - reading requires /dev/mem (may be locked by kernel)"
sudo dd if=/dev/mem bs=1 skip=$((0x5B134000)) count=1 2>/dev/null | od -An -tu1 \
  || echo "(/dev/mem locked - CONFIG_STRICT_DEVMEM, expected on Ubuntu)"

echo
echo "Tables decompiled into: $D/acpi/"
