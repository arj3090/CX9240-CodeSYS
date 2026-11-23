(* SPDX-License-Identifier: MIT *)
(* Copyright (c) 2026 Manufacturing Automation, LLC *)
(*
  FB_CX9240_UpsRetain - CX9240 internal UPS under CODESYS Control for Linux, in one block:
    - reads the power-fail signal of the internal UPS
    - saves the application's RETAIN variables when the supply is lost, and forces the file
      to disk so the runtime loads it again at the next start

  It replaces the two separate blocks FB_CX9240_Ups and FB_CX9240_RetainSave.

  Needs:
    - Libraries "SysFile" and "CmpApp" in the Library Manager.
    - On the controller, in /etc/codesyscontrol/CODESYSControl_User.cfg (the ccat-cx9240-dkms
      package adds this by itself):
          [SysFile]
          PlaceholderFilePath.1=/sys/class/power_supply/ups, $ups$

  Call it once per cycle from a fast cyclic task:
          fbUps();
  xPowerFail goes TRUE when the controller's 24 V supply is lost. On the tested unit the
  controller then ran on for about 6 s; design for 1 s (Beckhoff's rating). The E-bus
  terminals lose power about 5 ms after the signal, so outputs cannot be held.

  Saving (about 0.1 s, blocks the calling task):
    1. store all RETAIN variables to  <app>/<app>.tmp
    2. force that file to disk
    3. delete the old <app>/<app>.ret and rename the .tmp to that name
    4. force that change to disk
  The runtime loads <app>/<app>.ret by itself at start; no restore code is needed.

  Values on disk are as of the last save. Pulse xSaveRequest before a commanded restart or
  reboot, otherwise older values come back.
*)
FUNCTION_BLOCK FB_CX9240_UpsRetain
VAR_INPUT
    xSaveOnPowerFail : BOOL := TRUE;  (* save the RETAIN data when power fails *)
    xSaveRequest     : BOOL;          (* optional: save on rising edge *)
    sTmpFile : STRING := 'Application/Application.tmp';   (* change if the application *)
    sRetFile : STRING := 'Application/Application.ret';   (* is not named "Application" *)
END_VAR
VAR_OUTPUT
    (* power-fail signal *)
    xPowerFail      : BOOL;       (* TRUE = supply lost, running from the UPS capacitor *)
    xValid          : BOOL;       (* TRUE = status file was read successfully this cycle *)
    sStatus         : STRING(31); (* raw text from the kernel: "Charging" / "Not charging" *)
    udiReadErrors   : UDINT;      (* number of failed reads since start *)
    (* retain save *)
    xSaveDone       : BOOL;       (* at least one save has completed since start *)
    udiSaveCount    : UDINT;      (* number of saves since start *)
    tSaveDuration   : TIME;       (* how long the last save took *)
    udiStoreResult  : UDINT;      (* 0 = OK, storing the retains *)
    udiFlush1Result : UDINT;      (* 0 = OK, forcing the data to disk *)
    udiRenameResult : UDINT;      (* 0 = OK *)
    udiFlush2Result : UDINT;      (* 0 = OK, forcing the rename to disk *)
END_VAR
VAR
    (* status file *)
    hStatus   : POINTER TO BYTE;
    xOpen     : BOOL;
    abyBuf    : ARRAY[0..31] OF BYTE;
    nRead     : __XWORD;
    i         : INT;
    (* retain save *)
    pApp      : POINTER TO CmpApp.APPLICATION;
    hFile     : POINTER TO BYTE;
    xPrevFail : BOOL;
    xPrevReq  : BOOL;
    xDoSave   : BOOL;
    tStart    : TIME;
    res       : UDINT;
END_VAR

(* ================= implementation ================= *)

(* ---------- 1. read the UPS status ---------- *)
IF NOT xOpen THEN
    (* '$$' is a literal dollar sign in an IEC string: the path sent is $ups$/status *)
    hStatus := SysFileOpen('$$ups$$/status', ACCESS_MODE.AM_READ, ADR(res));
    xOpen := (res = 0);
END_IF

xValid := FALSE;
IF xOpen THEN
    SysFileSetPos(hStatus, 0);
    nRead := SysFileRead(hStatus, ADR(abyBuf), SIZEOF(abyBuf) - 1, ADR(res));
    IF nRead > 0 THEN
        xValid := TRUE;
        (* 'N' (16#4E) is the first letter of "Not charging" *)
        xPowerFail := (abyBuf[0] = 16#4E);
        sStatus := '';
        FOR i := 0 TO TO_INT(nRead) - 1 DO
            IF abyBuf[i] < 16#20 THEN EXIT; END_IF
            sStatus[i] := abyBuf[i];
            sStatus[i + 1] := 0;
        END_FOR
    ELSE
        (* read failed: close and reopen next cycle; keep the last xPowerFail value *)
        udiReadErrors := udiReadErrors + 1;
        SysFileClose(hStatus);
        xOpen := FALSE;
    END_IF
ELSE
    udiReadErrors := udiReadErrors + 1;
END_IF

(* ---------- 2. save the RETAIN data on power fail or on request ---------- *)
IF pApp = 0 THEN
    pApp := AppGetCurrent(ADR(res));
END_IF

xDoSave := (xSaveOnPowerFail AND xPowerFail AND NOT xPrevFail)
        OR (xSaveRequest AND NOT xPrevReq);

IF xDoSave AND pApp <> 0 THEN
    tStart := TIME();

    udiStoreResult := AppStoreRetainsInFile(pApp, sTmpFile);

    hFile := SysFileOpen(sTmpFile, ACCESS_MODE.AM_READ_PLUS, ADR(res));
    IF res = 0 THEN
        udiFlush1Result := SysFileFlush(hFile);
        SysFileClose(hFile);
    ELSE
        udiFlush1Result := res;
    END_IF

    IF udiStoreResult = 0 THEN
        (* the rename does not replace an existing file, so remove the old one first;
           its result is ignored because the file may not exist yet *)
        SysFileDelete(sRetFile);
        udiRenameResult := SysFileRename(sTmpFile, sRetFile);
        hFile := SysFileOpen(sRetFile, ACCESS_MODE.AM_READ_PLUS, ADR(res));
        IF res = 0 THEN
            udiFlush2Result := SysFileFlush(hFile);
            SysFileClose(hFile);
        ELSE
            udiFlush2Result := res;
        END_IF
    END_IF

    tSaveDuration := TIME() - tStart;
    udiSaveCount := udiSaveCount + 1;
    xSaveDone := TRUE;
END_IF
xPrevFail := xPowerFail;
xPrevReq  := xSaveRequest;


(* ================= example use in PLC_PRG =================
VAR
    fbUps : FB_CX9240_UpsRetain;
END_VAR
VAR RETAIN
    udiRunSeconds : UDINT;      // example of a value that must survive a power cut
END_VAR

fbUps();
// fbUps.xPowerFail is available for your own logic
*)
