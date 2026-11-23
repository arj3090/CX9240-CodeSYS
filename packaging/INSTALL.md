# ccat-cx9240-dkms 1.0 — install on a clean CX9240 image

Linux netdev driver for the CX9240's internal EtherCAT master. After install the bus is
network interface `eth0`, usable by CODESYS Control (or any raw-socket EtherCAT master).

## Prerequisites on the image
- Beckhoff RT Linux (Debian 13), `aarch64`. Tested on kernel `7.2.13-rt5-bhf-436945-52e30b343116`.
- Working `apt` access to the Beckhoff repositories. A freshly flashed image has none: every
  download returns `401 Unauthorized` until you create `/etc/apt/auth.conf.d/bhf.conf`
  (mode 600) with your myBeckhoff login, then run `sudo apt update`:
  ```
  machine deb.beckhoff.com login <email> password <password>
  machine deb-mirror.beckhoff.com login <email> password <password>
  ```
- Nothing else needs installing by hand. The package depends on `linux-headers-bhf`, `dkms`,
  `gcc` and `make`, and `apt` fetches them (about 100 packages, a few minutes, on a clean image).
- TwinCAT runtime **not** installed: the package conflicts with `tc31-xar-um`.
- About 64 MB free CMA memory (`grep Cma /proc/meminfo`; the tested image has 128 MB total).

## Install
```
scp ccat-cx9240-dkms_1.0-7_all.deb Administrator@<controller>:
sudo apt install ./ccat-cx9240-dkms_1.0-7_all.deb
```
The install builds the four modules with DKMS, enables `ccat-ecat.service`
(ordered before `codesyscontrol.service`) and brings `eth0` up immediately.

Check:
```
dkms status                 # ccat-cx9240/1.0, <kernel>, aarch64: installed
systemctl status ccat-ecat  # active (exited)
ip -br link show eth0       # UP ... LOWER_UP with a terminal attached
```
Then install CODESYS Control, add an EtherCAT Master in the project and select adapter `eth0`.
If CODESYS was already running when the package was installed: `sudo systemctl restart codesyscontrol`.

## Open the firewall for CODESYS
The image's firewall drops all inbound traffic except SSH and the Beckhoff services, so the
CODESYS IDE cannot find or connect to the runtime until its ports are opened. This is not part
of the driver package. Create `/etc/nftables.conf.d/60-codesys.conf`:
```
table inet filter {
  chain input {
    # CODESYS runtime, gateway and network scan
    tcp dport { 1217, 11740 } accept
    udp dport 1740-1743 accept
  }
}
```
then apply it (it also persists across reboots):
```
sudo systemctl reload nftables
sudo nft list chain inet filter input | grep 11740   # should show the rule
```
On first connect a fresh runtime asks the IDE to create a user and to trust its certificate.

## What gets installed
| Path | Purpose |
|---|---|
| `/usr/src/ccat-cx9240-1.0/` | driver source + `dkms.conf` (rebuilt automatically on kernel updates) |
| `/usr/lib/ccat-cx9240/ccat-ecat-start.sh` | loads modules, disables IPv6 on eth0, brings it up |
| `/usr/lib/systemd/system/ccat-ecat.service` | boot service |
| `/usr/lib/systemd/network/05-ccat-ecat-unmanaged.network` | keeps systemd-networkd/DHCP off the bus |
| `/usr/lib/ccat-cx9240/codesys-ups-setup.sh` | adds/removes the UPS path entry in the CODESYS runtime config |
| `/usr/lib/ccat-cx9240/codesys-tcled.sh` + `codesys-tcled.service` | TC LED green/red from CODESYS bus activity |
| `/usr/lib/systemd/system/ccat-ups-codesys.path` + `.service` | run that script when the CODESYS config file appears |
| `/usr/share/doc/ccat-cx9240-dkms/` | README, `UPS.md` (UPS measurements), and `examples/`: test programs `ecat_op.c`, `ecat_loop.c`, UPS tools `upslog.c`, `upsbus.c`, function block `FB_CX9240_UpsRetain.st` |

## Internal UPS: power-fail signal and retain data in CODESYS
The CX9240's internal UPS is a kernel device (`/sys/class/power_supply/ups`, `status` reads
`Charging` or `Not charging`). The package makes it readable from a CODESYS program:

- **Controller side, automatic.** The package adds this to
  `/etc/codesyscontrol/CODESYSControl_User.cfg` and restarts the runtime once:
  ```
  [SysFile]
  PlaceholderFilePath.1=/sys/class/power_supply/ups, $ups$
  ```
  It does so at install if CODESYS is already there, or later when CODESYS is installed.
  `apt remove` takes the line out again. To do it by hand:
  `sudo /usr/lib/ccat-cx9240/codesys-ups-setup.sh add` (or `remove`).
- **Project side, by hand.** Add libraries SysFile and CmpApp, create the function block
  `FB_CX9240_UpsRetain` from `examples/FB_CX9240_UpsRetain.st`, declare the data to keep as
  `VAR RETAIN`, and call it every cycle from a fast task:
  ```
  fbUps : FB_CX9240_UpsRetain;
  fbUps();
  ```
  (Up to package 1.0-4 this was two separate blocks, `FB_CX9240_Ups` and `FB_CX9240_RetainSave`.)

Measured on one unit (details in `UPS.md`): the controller runs about 6 s after supply loss,
the E-bus terminals lose power about 5 ms after the signal, and saving 4 KB of retain data and
forcing it to disk takes about 0.1 s. Beckhoff rates this UPS class at 1 s; design for that.
Retain values on disk are as of the last save: a restart without a power failure brings back
older values unless the program pulses `xSaveRequest` first.

## TC LED: CODESYS run/stop indication
The "TC" LED on the front is driven by the CCAT FPGA, not by a Linux GPIO. The package adds:

- Kernel module `ccat_tcled`: the LED as three standard LED devices, `/sys/class/leds/red:tc`,
  `green:tc` and `blue:tc` (write 0 or 1 to `brightness`). Register found by experiment:
  0xA0000300, bit 0 red, bit 1 green, bit 2 blue. Red and green are confirmed by eye; blue is
  assumed from the bit order.
- `codesys-tcled.service`: **green** while the CODESYS runtime is sending EtherCAT frames,
  **red** when it has sent none for 1.5 s, or the runtime is not running. No PLC code needed.
  Enabled at install; `sudo systemctl disable --now codesys-tcled` turns it off and leaves the
  LED free for your own use.

Limits: the LED follows bus activity, not the application state as such. A project without an
EtherCAT master on `eth0` always shows red, and a stopped bus looks like a stopped application.
Watching the PLC task threads does not work (they keep waking while the application is
stopped). The runtime's own event socket (`/var/opt/codesyscontrolapi/events.sock`) would give
the real state, but its request format is unknown.

Driver change that came out of this: versions up to 1.0-3 wrote 0 then 4 to that register at
load as a supposed "master enable". It only set the LED blue. The write is removed in 1.0-4.

## Remove
```
sudo apt remove ccat-cx9240-dkms
```

## Rebuild the .deb after changing the source
Edit files under `ccat-cx9240-dkms_1.0_all/`, set the new `Version` in `DEBIAN/control`, and
run `build-deb.sh` on any Debian or Ubuntu system. On the Windows PC that is the Debian
installed under WSL:
```
wsl -d Debian -- sh /mnt/<drive>/<path-to-repo>/packaging/build-deb.sh
```
The script copies the tree to a Linux folder, sets the file modes, builds
`ccat-cx9240-dkms_<version>_all.deb` and puts it next to itself.
(It has to be built by Linux tools, not Windows ones — file modes matter. For a change to the
driver source itself, also bump
`PACKAGE_VERSION` in `dkms.conf`, `VER` in `postinst`/`prerm` and the `/usr/src` folder name together.)

## Test status
- Tested 2026-11-21 on one CX9240 (FPGA build 2026-07-02) with one EL2008: package install,
  DKMS build, reboot, CODESYS boot application running the bus, 0 frame errors.
- Tested 2026-11-21 on a freshly flashed image (no headers, compiler, dkms, TwinCAT or CODESYS):
  version 1.0 failed there because it did not depend on the kernel headers; version 1.0-2
  installs in one `apt install`, and after a reboot `ecat_op` took the EL2008 to OP and ran
  2500 cyclic frames with 0 lost. CODESYS Control 4.21.0.0 was then installed on that image
  and, once the firewall was opened, the IDE connected and the PLC program switched the
  EL2008 output on.
- Two terminals (EL2008 + EL4024): the CODESYS scan found and identified both. Running both
  reached OP under CODESYS (EL4024 is configured over the CoE mailbox), about 250 frames/s
  with 0 interface errors over ~78,000 frames. The EL4024 analog outputs were confirmed with a meter.
- Distributed clocks, 4 ms cycle, EL4024 in DC-Synchron as reference clock: reached OP and
  stayed there. Measured passively from the reference clock's own time over 60 s (15,000
  frames): average frame interval 4,000,002 ns, min 3.874 ms, max 4.152 ms, 17 intervals off
  by more than 100 µs, none by more than 500 µs, no missed cycle. Arrival phase held at about
  0.83 ms into the cycle (master sync offset 20 % = 0.8 ms), so the master is locked to the
  slave clock. Only one DC slave was present, so slave-to-slave deviation was not measured.
- Same test at a 1 ms cycle, 60 s (60,000 frames): average interval 1,000,000 ns, min 0.906 ms,
  max 1.059 ms, 9 intervals off by more than 50 µs, none by more than 100 µs, no missed cycle,
  0 interface errors. Arrival phase held at about 0.24 ms (sync offset 20 % = 0.2 ms).
  To get 1 ms: set the EtherCAT master's Distributed Clock "Cycle time" to 1000 µs in the
  project (typing 1 ms into EtherCAT_Task alone left the bus at 4 ms). No runtime config
  change is needed: that run had `SchedulerInterval` in `CODESYSControl.cfg` set to 1000, and
  a repeat with the default 4000 gave the same result (min 0.932 ms, max 1.070 ms, 13 intervals
  off by more than 50 µs, none by more than 100 µs, no missed cycle). The default is restored.
- Same test at a 500 µs cycle (2,000 frames/s), both terminals in OP, 0 interface errors.
  Run 1, 60 s (120,000 frames): one 13.5 ms gap (about 26 cycles with no frame), otherwise
  within 54 µs of nominal; the terminals stayed in OP and CODESYS logged nothing. Run 2,
  180 s (360,000 frames): no gap, min 0.446 ms, max 0.555 ms, 8 intervals off by more than
  50 µs, none by more than 100 µs, listener dropped 0 frames. The cause of the single gap is
  unknown and it was not reproduced; treat 500 µs as working but not proven stall-free.
- Version 1.0-3 (adds UPS support files): installed as an upgrade over 1.0-2 on the tested
  controller. The UPS config entry was added at install and the running PLC then read the UPS
  status; the "CODESYS installed later" path was tested by taking the config file away and
  putting it back, not by a real CODESYS install. **Not** tested on a freshly flashed image,
  and no supply pull was done after installing this version.
- **Not** tested with Secure Boot enforcing module signatures (DKMS signs with its own
  self-generated key; this image does not enforce), with a different kernel version, with
  cycle times shorter than 500 µs, with more than one DC slave, or with more than two terminals.
- Assumes the new interface is named `eth0` (built-in ports on this image are `end0`/`end1`).
- Version 1.0-4 (TC LED, old LED-register write removed from the driver): installed as an
  upgrade over 1.0-3 and rebooted. After the reboot the bus came up without the removed write
  (2,015 frames/s, 0 errors, all slaves operational), the LED service went red at start and
  green 16 s later when CODESYS began cycling the bus, and retain data was loaded. Stop -> red
  and start -> green were confirmed by eye with the same script before packaging, not again
  after the reboot. **Not** tested on a freshly flashed image.
- Version 1.0-4 on a freshly flashed image, 2026-11-22, installed by
  `setup_script/Install-CX9240.ps1` (driver package, the four CODESYS 4.21.0.0 packages installed
  directly with apt instead of the IDE Deploy tool, firewall rule). The script ended with all
  eight checks OK: DKMS build, eth0 up, driver service, CODESYS runtime, TC LED service, firewall
  rule, UPS entry in the CODESYS configuration (added automatically, by a real first-time
  install this time) and UPS signal. Ports 11740 and 1217 answered from the PC. The CODESYS IDE
  then connected and ran the project on the bus. **Not** yet done on that image: a reboot.
- Version 1.0-5, 2026-11-22: the two function blocks in `examples/` replaced by the combined
  `FB_CX9240_UpsRetain.st`, and `UPS.md` refreshed. Built with `build-deb.sh` under WSL. Compared
  with 1.0-4: same file modes and owners, identical install scripts, and no difference in any
  file other than those two documentation items and the version number. The driver,
  services and scripts are byte-for-byte those of 1.0-4.
- Version 1.0-5 installed 2026-11-22 as an upgrade over 1.0-4, by a second run of the setup
  script on the controller that had been set up from a fresh image earlier that day. The
  script reported the package installed and `eth0` present, and all eight checks OK (DKMS
  build, eth0 up, driver service, CODESYS runtime, TC LED service, firewall rule, UPS entry,
  UPS signal); ports 11740 and 1217 answered from the PC afterwards. The project
  was running again afterwards with the TC LED green. The controller was then rebooted
  and came back up by itself. The installed version was not read back from the controller
  directly.
- Version 1.0-6: the package's own README replaced by a short one. No other change from 1.0-5.
  **Not** installed on a controller.
- Version 1.0-7: licence and copyright header lines added to the source files written for this project and
  scripts. Comment lines only; no change to any code. **Not** installed on a controller.
