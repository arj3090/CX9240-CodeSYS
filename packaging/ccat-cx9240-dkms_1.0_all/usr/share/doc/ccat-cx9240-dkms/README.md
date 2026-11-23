# ccat-cx9240-dkms

Linux support for the Beckhoff CX9240 embedded PC under Beckhoff RT Linux, so that a Linux
EtherCAT master such as CODESYS Control can use the controller without the TwinCAT runtime.

This is a bench project, not a Beckhoff or CODESYS product. It was developed and tested on one
CX9240 with an EL2008 and an EL4024.

## What the package provides
| Part | Purpose |
|---|---|
| Kernel modules `ccat`, `ccat_netdev`, `ccat_cx_shim` | The internal EtherCAT master (CCAT FPGA) as network interface `eth0` |
| Kernel module `ccat_tcled` | The TC front LED as Linux LEDs `red:tc`, `green:tc`, `blue:tc` |
| `ccat-ecat.service` | Loads the driver and brings `eth0` up at boot, before CODESYS |
| `codesys-tcled.service` | TC LED green while CODESYS cycles the bus, red otherwise |
| `ccat-ups-codesys.path` / `.service` | Lets CODESYS programs read the internal UPS status |
| `examples/` | Function block `FB_CX9240_UpsRetain.st`, EtherCAT and UPS test programs |
| `UPS.md` | Measurements of the internal UPS |

## Hardware findings the driver relies on
These were found by experiment on one unit (FPGA build 2026-07-02). They are not from Beckhoff
documentation and may not hold for other builds.

- The CCAT FPGA is at physical address `0xA0000000`. Its EtherCAT-master-with-DMA function
  (type `0x14`) is at `0xA0020000`.
- **The DMA buffers must start on a 16 MB boundary.** The hardware forms the bus address from
  the top 8 bits of the base register and a 24-bit offset in each descriptor. With a smaller
  alignment no frames are received, and the FPGA can write to unrelated memory.
- Received frames carry a 16-byte header and a 4-byte checksum; the payload length is the
  header's length field minus 20.
- The CCAT GPIO function (type `0x0d`) at `0xA0000300` drives the TC LED: bit 0 red, bit 1
  green, bit 2 blue. Red and green are confirmed by eye; blue is assumed from the bit order.
- The internal UPS is a kernel `gpio-charger` device, `/sys/class/power_supply/ups`. Its
  `status` reads `Charging` with supply present and `Not charging` after supply loss.

## Origin and licence
`module.c`, `module.h` and `netdev.c` come from Beckhoff's open-source CCAT driver and keep
their original licence headers. The other files were written for this project. See the
licence notes in the repository.
