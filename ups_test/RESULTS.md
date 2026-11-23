# CX9240 internal UPS — power-loss measurement

> The raw log files named in this document (`stream_run*.log`, `disk_run*.log`) are not part of this repository; the tables below hold what was read from them.

## Interface (Beckhoff RT Linux, kernel 7.2.13-rt5-bhf)
- Device: `/sys/class/power_supply/ups` (kernel `gpio-charger`, device tree node `/ups`).
- `status`: `Charging` with supply present, `Not charging` after supply loss. Backed by GPIO 17
  with an interrupt, so the kernel also emits a udev `change` event.
- `constant_charge_current_max`: charge-current-limit GPIO 19 (not touched in this test).
- No voltage, charge level or remaining-time reading exists.
- Beckhoff's `upsservice-bhf` package is for external USB UPS units (CU81xx), not this one.

## Run 1 — 2026-11-21, supply removed once, CODESYS running the bus at 500 µs
Tool: `upslog.c` (1 ms polling at SCHED_FIFO 40; stream to another machine over ssh every 2 ms;
after the status change, numbered records written to btrfs and forced out with `fdatasync`).

| Measure | Result |
|---|---|
| Status before | `Charging` (about 12 min after boot) |
| Status change | `Not charging`, seen 102.806 s into the run |
| Last line received over the network | 5.863 s after the change, no gaps in the stream |
| Last record committed to disk | seq 72, finished 5.748 s after the change |
| Disk commits completed after the change | 73 (mean 78.6 ms, max 155.7 ms each) |
| After power returned | booted normally, status `Charging` again |

Files: `stream_run1.log` (network stream), `disk_run1.log` (what survived on disk).

## Run 2 — 2026-11-21, about 2 min after boot, CODESYS running the bus
Power was removed by unplugging the 24 V connector at the controller with the supply left on.
The supply is also a very small one with little stored energy, so it did not meaningfully
extend run 1 either: about 5.9 s is the hold-up of this unit's UPS under this load.

| Measure | Result |
|---|---|
| Status change | `Not charging`, seen 46.234 s into the run |
| Last line received over the network | 5.879 s after the change, no gaps in the stream |
| Last record committed to disk | seq 124, finished 5.791 s after the change |
| Disk commits completed after the change | 125 (mean 46.2 ms, max 73.9 ms each) |
| After power returned | booted normally, status `Charging` again |

Files: `stream_run2.log`, `disk_run2.log`.

The two runs ended 5.863 s and 5.879 s after the status change, 16 ms apart, despite very
different time since boot (12 min vs 2 min). A discharging capacitor would not be expected to
repeat that closely, so the run time after supply loss may be set by a fixed timer in the
power electronics rather than by the stored charge. This is an inference from two runs, not
a documented fact.

## Limits of this result
- One run only. Hold-up will vary with capacitor charge, age, temperature and load.
- The delay between the physical loss of supply and the status change is not measured.
- Run 1 removed power by switching off the 24 V power supply; run 2 by unplugging the connector.
  Both gave the same hold-up, so the supply's output capacitors were not a factor.
- Two runs on one new unit at room temperature, with two terminals on the E-bus.
- Beckhoff documents this UPS class as "1-second"; design for 1 s, not for the measured value.

## Reading the signal from a CODESYS program
- Controller: added to `/etc/codesyscontrol/CODESYSControl_User.cfg` (original kept beside it as
  `CODESYSControl_User.cfg.before-ups`), then restarted the runtime:
  ```
  [SysFile]
  PlaceholderFilePath.1=/sys/class/power_supply/ups, $ups$
  ```
  The runtime user `codesyscontrol` can read the status file without extra permissions.
- Project: `FB_CX9240_Ups.st` (needs the SysFile library). Compiles and runs: with supply
  present `xValid` is TRUE and `sStatus` reads `Charging`. The power-fail transition was
  confirmed in run 4 (`xPowerFail` went TRUE and the PLC reacted within 0.5 ms).

## Run 3 — 2026-11-21, combined UPS status + bus capture (`upsbus.c`), 500 µs bus cycle
Capture counts only frames that return from the terminals, and logs the first output byte of
the cyclic write (bit 0 = EL2008 output 1). File: `stream_run3_plc.log`.

| Event | Time after UPS status change |
|---|---|
| UPS status `Charging` -> `Not charging` | 0 |
| Last process-data frame returned from the terminals | +5.5 ms |
| Output byte at that point | still 0x01 (no change seen) |
| Last line received over the network | +6.39 s (line spacing 160 ms, so death at 6.39-6.55 s) |

What this shows:
- The E-bus stops answering about 5 ms after the status change. That fits Beckhoff's statement
  that the UPS does not supply the terminals. The PLC therefore cannot command a safe output
  state after power fail; the terminals are already unpowered (outputs drop on their own).
- No PLC reaction was seen on the bus in those 5.5 ms. Whether the program had a reaction on
  `xPowerFail`, and which task called the block, was not confirmed, so this neither proves nor
  disproves the PLC-side transition.
- Hold-up was about 6.4 s here against 5.86 s and 5.88 s in runs 1 and 2. The "fixed timer"
  idea from run 2 is therefore wrong; hold-up varies by at least 0.5 s between runs.
- Use of the signal is limited to what the CPU can do alone: saving retain/persistent data,
  closing files, logging.

## Side finding from run 3: unsynced files are lost
The capture binary `upsbus` was compiled about 40 s before the supply was pulled and never
explicitly synced. After reboot it existed with a length of 0 bytes. Hold-up time does not
flush the filesystem by itself: anything that must survive a power loss has to be forced to
disk (`fsync`/`sync`) when the power-fail signal arrives. The logger's records, which were
synced one by one, all survived.

## Run 4 — 2026-11-21, PLC reaction, MainTask at 1 ms, bus cycle 500 µs
Program: `fbUps(); IF fbUps.xPowerFail THEN OUT0 := FALSE; ELSE OUT0 := TRUE; END_IF`
File: `stream_run4_plc.log` (the bus stall from 93.8 s to 118.7 s in it is the project download).

| Event | Time after UPS status change |
|---|---|
| UPS status `Charging` -> `Not charging` | 0 |
| Output byte on the bus 0x01 -> 0x00 (PLC reacted) | +0.5 ms |
| Last process-data frame returned from the terminals | +5.5 ms (both terminals still acknowledging) |
| Last line received over the network | +6.37 s |

`FB_CX9240_Ups.xPowerFail` is therefore confirmed from the PLC: the application saw the power
failure and its changed output reached the terminals about 5 ms before the E-bus stopped.
That 5 ms margin is too small to rely on for outputs; the terminals lose power regardless.

## Run 5 — 2026-11-21, saving RETAIN data on power fail (first version of FB_CX9240_RetainSave)
File: `stream_run5_retain.log` (UPS status and retain file presence, sampled about every 45 ms).

| Event | Result |
|---|---|
| Temporary file written (4120 bytes) | seen in the same sample window as the status change |
| Renamed to the final file | about 105 ms after the status change |
| Controller stopped | about 6.0 s after the status change |
| After reboot | file present, 4120 bytes, contains the counter value (202) |

Save side: works, and the file survives the power cut.

Restore side, found by reading the runtime log:
- At start the runtime itself looks for `PlcLogic/Application/Application.ret`. With that file
  missing it logs "Retain restore from file failed ... Loading retain data failed".
- With the saved file copied to that name and the runtime restarted, it logs
  "Retains matched to bootproject". So no restore code is needed in the program.
- The runtime did not write that file on power loss or on `systemctl restart codesyscontrol`.

`FB_CX9240_RetainSave.st` was therefore changed to write straight to
`Application/Application.ret` (via a temporary file and rename), the restore call was removed,
and a `xSaveRequest` input was added. **The changed version has not been compiled or run.**

## Run 6 — 2026-11-21, changed block writing to Application/Application.ret — FAILED
After the pull and reboot, on the controller:
- `Application/Application.tmp` — 4120 bytes, written at the power cut (23:05:25). Saved and on disk.
- `Application/Application.ret` — still the file from run 5 (22:56:25). Not replaced.
- The runtime loaded the old `.ret` at boot ("Retains matched"), i.e. stale values.

So store and flush worked, but the rename onto an existing file did not take effect. Whether
`SysFileRename` refused because the target existed, or the rename was not committed to disk
before power ran out, is not known. Fix applied to `FB_CX9240_RetainSave.st`: delete the old
`.ret` before renaming. **Not yet compiled or tested.**

## Run 7 — 2026-11-21, block with delete-before-rename — PASSED
After the pull and reboot, on the controller:
- `Application/Application.ret` — 4120 bytes, timestamp 23:09:39, the second of the power cut
  (the previous boot's last journal entry is also 23:09:39). Contains the counter value 403.
- No `.tmp` file left behind.
- Runtime log at boot: "Retains matched to bootproject of application [Application]".

The saved file replaced an existing retain file, survived the power cut and was loaded by the
runtime. In the IDE after reboot the RETAIN counter resumed from the saved value, confirming
the whole chain from power-fail signal to restored program data.

## How to use it in a project (summary)
1. Controller: add the `[SysFile] PlaceholderFilePath.1=/sys/class/power_supply/ups, $ups$`
   lines to `/etc/codesyscontrol/CODESYSControl_User.cfg` and restart the runtime.
2. Project: libraries SysFile and CmpApp; function blocks `FB_CX9240_Ups` and
   `FB_CX9240_RetainSave`; call both every cycle from a fast task:
   `fbUps(); fbRetain(xPowerFail := fbUps.xPowerFail);`
3. Declare the data to keep as `VAR RETAIN`.

Known limits: retain values on disk are as of the last save (power fail or `xSaveRequest`);
a service restart or reboot without a save brings back older values. A project download
normally clears retain data. Tested on one controller, 4 KB of retain data, 3 pulls.

## Combined function block (2026-11-22)
`FB_CX9240_UpsRetain.st` joins `FB_CX9240_Ups` and `FB_CX9240_RetainSave` into one block with a
single call (`fbUps();`). It compiles and reads the UPS status (`Charging`) in the test
project. The power-fail save has **not** been repeated with the combined block; its save code
is the same as in the separate block that passed run 7.
The file is also copied into the package source tree, but the built package 1.0-4 does not
contain it; it will be included the next time the package is rebuilt.
