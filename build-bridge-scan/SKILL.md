---
name: build-bridge-scan
description: 'Step 1 of Build Bridge: a read-only scan of the PC. Use after the owner says YES to the read-only scan, and again at the end of the rollback drill.'
---

# Build Bridge, step 1: read-only scan

## Purpose
Read the starting state of this PC and change nothing, so the rollback drill can prove everything was put back.

## Steps

Ask first: "Step 1 only reads your computer and changes nothing. The scan script runs with `-ExecutionPolicy Bypass`. That flag only lets PowerShell run this one script file for that one run. It changes no system setting and does not turn off any of Build's approvals. Reply YES to run the scan." Wait for YES.

Run on the person's own computer:
- Windows (see Limits): `scan.ps1` in this folder. Paste it as one command or save to `%TEMP%` and run `powershell -NoProfile -ExecutionPolicy Bypass -File <TEMP>\bb-scan.ps1 -ProjectDir "<PROJECT_DIR>"`. One live run on one Windows 11 PC (PowerShell 5.1, Grok Build 1.0.70) passed the steps in TEST-LOG.md. The v1.0.1 keygen fix (bb-keygen.ps1 9072ed42) then passed a separate test-mode run on Windows PowerShell 5.1 (see TEST-LOG.md); the v1.0.1 webhook.json and auto-hmac.key write paths passed in test mode only (PC, PS 5.1); a one-hour live soak passed on one PC with auto-pickup off (see TEST-LOG.md). The step 7 installer (`install-launch-task.ps1`) passed on one Windows 11 PC (PowerShell 5.1): TASK-INSTALL-OK, launch task result 0, and the already-running guard held (see TEST-LOG.md). Longer soaks, auto-pickup and the rest stay [UNTESTED]: macOS/Linux, autopickup and 4c auto mode, mid-session idle pickup, sign-out/sign-in, soaks longer than one hour, multiple PCs.
- Why `%TEMP%` and not the installed folder: the scan runs at step 1, before `<USER_HOME>/.buildbridge` exists, and again after the rollback drill has moved that folder aside. An installed copy would not be there either time, and keeping one would make the two scans differ. So the scan always runs from a temp copy. That copy is outside the folders the scan checks, and you can delete it after.
- The scan imports the shared launcher-name check from `bb-common.ps1` (in `build-bridge-signing`). Save that file next to the scan copy in `%TEMP%`, or run the scan from the unzipped package, where it finds `..\build-bridge-signing\bb-common.ps1` by itself. bb-common is read-only too: it only defines helpers.

It reports: OS, shell, terminal (Windows Terminal), whether `grok` is installed and its version, whether Build is running for `<PROJECT_DIR>`, whether `~/.buildbridge` and `~/.buildbridge-keys` exist, any Build Bridge task, any running watcher, and whether `<PROJECT_DIR>/AGENTS.md` already holds the Build Bridge block. It never prints file contents or key values.

Then, from Grok Bot's own side: list the person's connected computers and name which one Build lives on; ask for their own webhook routine (never ship one).

Save the before-scan automatically: add `-Save 1`. It writes `<root>-scans/scan-1.txt`, where `<root>` is `BB_HOME` or `<USER_HOME>/.buildbridge`. That folder sits next to `<root>` and `<root>-keys`, so the rollback, which moves only those two aside, never moves it. It refuses to overwrite an existing scan-1 (`SCAN-1-EXISTS`) and saves nothing if the scan did not finish (`SCAN-INCOMPLETE`). In test mode (`BB_TEST=1`), step 2 (`make-folders`) and `bb-on` refuse with `TEST-REFUSED: no before-scan` until scan-1 exists. After the rollback, `-Save 2` writes `scan-2.txt` next to it and prints `SCAN-MATCH` (exit 0) or `SCAN-DIFF` plus the differing lines (exit 1). It refuses with `SCAN-1-MISSING` if there is no scan-1.
- Every scan starts with `project=<sha256 of the project's full path>`, so the log carries no path. The compare needs the same `project=` line in both scans. A different or missing one gives `SCAN-PROJECT-MISMATCH` (exit 2), never a match.
- Only bridge-launched Builds are counted and compared: `bridge-grok-processes` and `bridge-build-running-for-project`. A Build counts when one of its ancestors runs a script from `<root>/bin` (the launcher tab host or a pickup run, which also set BB_LAUNCHED); in test mode `<root>` is the test BB_HOME. The person's own Build sessions show as `info: own-grok-processes` and `info: own-build-running-for-project`. `info: ` lines are reported but not compared, so opening Build by hand never causes SCAN-DIFF. Not tested: the Windows ancestor walk through Windows Terminal.

Stop rules: no grok binary, admin-only account, or an unsupported terminal → say so and stop before step 2.

## Check
The report ends with `SCAN-COMPLETE`.

## Undo
Without `-Save` nothing is written. With `-Save`, the only files are `<root>-scans/scan-1.txt` and `scan-2.txt`. They contain no keys, but they are a snapshot of this PC, such as the startup list. The rollback (step 8) offers to delete that folder with its own DELETE-SCANS prompt.
