# Licences

This repository contains files under different licences. The licence of a file is the one
stated in its own header; where a file has no header, the table below applies.

| Files | Origin | Licence |
|---|---|---|
| `packaging/ccat-cx9240-dkms_1.0_all/usr/src/ccat-cx9240-1.0/module.c`, `netdev.c` | Beckhoff CCAT driver, Copyright (C) Beckhoff Automation GmbH & Co. KG, modified for the CX9240 | MIT (`LICENSES/MIT.txt`), as stated in the file headers |
| `.../ccat-cx9240-1.0/module.h` | Beckhoff CCAT driver, Copyright (C) 2014 Beckhoff Automation GmbH | GNU General Public License, version 2 or later (`LICENSES/GPL-2.0.txt`), as stated in the file header |
| `.../ccat-cx9240-1.0/ccat_tcled.c`, `ccat_cx_shim.c` | Written for this project, Copyright (c) 2026 Manufacturing Automation, LLC | GNU General Public License, version 2 (`LICENSES/GPL-2.0.txt`) |
| Everything else: scripts, function block, test tools, documentation, screenshots | Written for this project, Copyright (c) 2026 Manufacturing Automation, LLC | MIT (`LICENSES/MIT.txt`) |

Copyright (c) 2026 Manufacturing Automation, LLC, for the files written for this project.
The changes made to the Beckhoff files for the CX9240 are Copyright (c) 2026 Manufacturing
Automation, LLC and are offered under the same licence as the file they are in.

The kernel modules built from these sources are loaded into a Linux kernel and are distributed
as a whole under the GNU General Public License, version 2.

## Not covered by these licences
- **Beckhoff RT Linux, TwinCAT and the Beckhoff device description files** are Beckhoff
  products with their own terms. None of them is included here.
- **CODESYS and the CODESYS runtime packages** are products of CODESYS GmbH with their own
  terms. None of them is included here; the setup script takes them from your own CODESYS
  installation.
- "Beckhoff", "TwinCAT", "EtherCAT" and "CODESYS" are trademarks of their respective owners.
  This project is not affiliated with or endorsed by Beckhoff or CODESYS.

## No warranty
This is a bench project, tested on one controller. It is provided as is, without warranty of
any kind. It drives real outputs; use it at your own risk.
