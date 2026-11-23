# CX9240 with CODESYS

Linux support for the Beckhoff **CX9240** embedded PC that lets **CODESYS Control for Linux**
run the controller's internal EtherCAT bus, without the TwinCAT runtime.

> **This is a bench project, not a Beckhoff or CODESYS product.** It was developed and tested on
> one CX9240 with two terminals (EL2008, EL4024). It relies on hardware behaviour found by
> experiment, not on vendor documentation. Read the limits in the guides before using it, and do
> not rely on it for anything that matters without testing it yourself.

## What you get
- **The internal EtherCAT master as a Linux network interface (`eth0`).** CODESYS uses it like any
  other EtherCAT adapter; the E-bus terminals show up in a CODESYS scan.
- **A power-fail signal from the internal UPS**, readable from a CODESYS program, and a function
  block that saves RETAIN data when the supply is lost.
- **The TC front LED showing the CODESYS state**: green while the runtime cycles the bus, red when
  it is stopped.
- **A setup script** that takes a freshly imaged controller to a working CODESYS target in one run.

## Start here
| If you want to | Read |
|---|---|
| Set a controller up with as little typing as possible | [Scripted install](docs/scripted-install.md) |
| Do the same steps by hand | [Quick install](docs/quick-install.md) |
| Understand what each step does, and see the measurements | [Full setup guide](docs/full-setup-guide.md) |

## What is in this repository
| Folder | Contents |
|---|---|
| `packaging/` | Source tree of the Debian package `ccat-cx9240-dkms` (kernel modules, services, scripts), the script that builds it, and install notes with the full test record |
| `setup_script/` | `Install-CX9240.cmd` / `.ps1` for the PC and `setup-controller.sh` for the controller |
| `ups_test/` | The function block `FB_CX9240_UpsRetain.st`, the UPS measurement tools and the results |
| `docs/` | The three guides and their screenshots |

The built package, `ccat-cx9240-dkms_1.0-7_all.deb`, is in `packaging/`. It can also be rebuilt
from the source tree with `packaging/build-deb.sh` on any Debian or Ubuntu system.

## What you need
- A Beckhoff CX9240 with E-bus terminals, running **Beckhoff RT Linux** (Debian 13, arm64).
- A **myBeckhoff account**, to download the image and so that the controller can fetch packages.
- A Windows PC with the **CODESYS Development System** and the add-on **CODESYS Control for Linux
  ARM64 SL**. Without a licence the CODESYS runtime runs in a two-hour demo mode.

Nothing from Beckhoff or CODESYS is included in this repository. You download their software
yourself, under their terms.

## Tested with
| Item | Version |
|---|---|
| Controller | One CX9240, FPGA build 2026-07-02 |
| Beckhoff RT Linux image | Build 440542, kernel `7.2.13-rt5-bhf` |
| CODESYS Development System | V3.5 SP22 Patch 2 |
| CODESYS Control for Linux ARM64 SL | 4.21.0.0 |
| Terminals | EL2008, EL4024 |

Bus cycle times of 4 ms and 1 ms ran cleanly in the tests; 500 µs worked but showed one
unexplained stall. Details are in the full guide.

## Things to know before you use it
- **TwinCAT cannot be installed alongside.** The package conflicts with the TwinCAT runtime,
  because both would own the internal EtherCAT master.
- **The setup script logs in with the controller's default password.** A newly imaged controller
  has the user `Administrator` with a well-known default password, and the script uses it so that
  it does not have to ask. **Change that password** as soon as the controller is set up; until
  then anyone on the same network can log in to it.
- **The script opens the CODESYS programming ports** in the controller's firewall. Keep the
  controller off untrusted networks.
- **Outputs are not held up by the UPS.** When the 24 V supply is lost the terminals lose power
  within milliseconds, whatever the program does.
- **Not tested:** a kernel update, other FPGA or image builds, more than two terminals, and long
  running times.

## Licence
Copyright (c) 2026 Manufacturing Automation, LLC.

The driver is based on Beckhoff's open-source CCAT driver, Copyright (C) Beckhoff Automation
GmbH & Co. KG. Files keep the licence stated in their headers; everything written for this
project is under the MIT licence, except the two new kernel modules, which are GPL version 2.
See [LICENSE.md](LICENSE.md).

Beckhoff, TwinCAT, EtherCAT and CODESYS are trademarks of their respective owners. This project
is not affiliated with or endorsed by them.
