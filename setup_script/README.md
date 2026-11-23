# CX9240 one-shot setup script

Replaces steps 5 to 8 of the quick install guide (Beckhoff login for `apt`, driver package,
CODESYS runtime, firewall rule) with one command run on the PC.

**Status: run once, successfully, on a freshly flashed controller (2026-11-22).** Image build
440542, package 1.0-4, CODESYS packages 4.21.0.0 taken from CODESYS 3.5.22.20. The
preset-password login worked for the copy, the login and `sudo`; the only thing typed was the
myBeckhoff login. All eight checks reported `OK`, and the CODESYS ports (11740, 1217) were then
reachable from the PC. The CODESYS IDE then connected to the runtime installed this way and ran
the project on the bus. A second run on that already set-up controller, this time with package 1.0-5, also finished
with all eight checks `OK`: it did not ask for the myBeckhoff login again, upgraded the driver
package and left CODESYS installed. The controller was then rebooted and came back up by itself.

After that second run, one line was added to `setup-controller.sh` so that it prints the
installed driver package version. That line has not been run yet.

## Use
1. Flash the microSD card, start the controller and find its address (quick install steps 1-3).
2. On the PC, double-click `Install-CX9240.cmd` and type the address, or in PowerShell:
   ```
   .\Install-CX9240.ps1 -Address 192.168.1.247
   ```
3. Type your myBeckhoff e-mail and password when asked (only when the controller does not
   have them yet). The controller's own password is not asked for: the script uses the one a
   newly imaged controller has (user `Administrator`, password `1`).
   - If the password has been changed: `.\Install-CX9240.ps1 -Address <addr> -AskPassword`
     to type it, or `-Password <value>` to preset another one.
   - **Change the default password** once the controller is set up (`passwd` on the
     controller). Until then anyone on the network can log in to it as administrator.
4. Wait for the list of checks. All lines should read `OK`.
5. Continue with Part 3 of the quick install guide, in CODESYS.

## What it needs on the PC
- `ccat-cx9240-dkms_*_all.deb` next to the script, or in `..\packaging`.
- CODESYS with the add-on *CODESYS Control for Linux ARM64 SL* installed. The script takes the
  runtime, gateway, privilege proxy and CodeMeter packages from the CODESYS installation
  folder; these are the same files the IDE's Deploy tool installs.
- The OpenSSH client that comes with Windows 10 and 11.

## Files
| File | Runs on | Purpose |
|---|---|---|
| `Install-CX9240.cmd` | PC | Double-click launcher, asks for the address |
| `Install-CX9240.ps1` | PC | Finds the files, copies them, starts the setup |
| `setup-controller.sh` | Controller | Does the five steps and prints the checks |

A log of the controller-side run is written to `/var/log/cx9240-setup.log`.

## Not covered
Writing the microSD card, finding the controller's address, and everything in the CODESYS
project (first user, EtherCAT master, scan).

## Notes from the first run
- Installing the four CODESYS packages directly with `apt`, in the order CodeMeter, proxy,
  runtime, gateway, worked without errors. Whether the result matches the IDE Deploy tool in
  every detail has not been compared.
- The CODESYS packages together took several minutes. The script prints one line per package
  and nothing in between, so it can look stuck.
- The last step (restart and checks) stayed silent for a minute or more before printing.
- A myBeckhoff password containing a space will not work in the credentials file.
- The preset-password login needs OpenSSH 8.4 or newer on the PC (9.5 was used). If it
  fails, use `-AskPassword`.
