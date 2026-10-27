---
name: build-bridge-launcher
description: 'Step 7 of Build Bridge: an on-demand launcher that opens one Grok Build session (never a second), plus remote start with no trigger. Use for step 7 and when Grok Bot needs to start Build remotely.'
---

# Build Bridge, step 7: launcher and on-demand remote start

## Purpose
Add a launcher that opens one Grok Build session only when asked, never a second, with no schedule and no trigger.

## Before you start: hands-off jobs
Hands-off jobs wait for a person; see build-bridge-watchers (hands-off jobs, the stall alert and clearing it).

## Steps
Ask: "Step 7 adds a launcher that opens one Grok Build tab for `<PROJECT_DIR>` only when asked. It has no schedule, no timer and never starts at sign-in. If Build is already running it does nothing. Reply YES." Wait for YES.

Files (copy to `<USER_HOME>\.buildbridge\bin\`; `install-launch-task.ps1` fills `<PROJECT_DIR>` and `<USER_HOME>` and checks none is left):
| | Windows |
|---|---|
| Launcher | `bb-launch.ps1` |
| Tab host (exits 0 so the tab closes) | `bb-build-tab.ps1` |
| On-demand job | `build-bridge-launch.task.xml` (template: Task Scheduler, `<Triggers />`, LeastPrivilege) |
| Task installer | `install-launch-task.ps1` (fills placeholders, registers, checks) |

The starting prompt lives in the tab host. It tells the new session to turn on the listener and check the outbox right away, because a Build session does not act on the AGENTS.md startup rule until it gets its first message (see build-bridge-startup-rule).

The tab host sets `BB_LAUNCHED=1` before starting Build, so allow-auto refuses inside a launched session. See build-bridge-watchers step 4c for the YES, the undo and the check.

Do it (no admin rights, per-user only; setup locks your own keys folder with icacls in step 3):
- Windows: copy `install-launch-task.ps1` and `build-bridge-launch.task.xml` from this folder into `<USER_HOME>\.buildbridge\bin\`, then run `powershell -NoProfile -File "<USER_HOME>\.buildbridge\bin\install-launch-task.ps1" -ProjectDir "<PROJECT_DIR>"` (this card adds no policy bypass; if your execution policy blocks the script, tell the person instead of working around it). It fills `<USER_HOME>` from `$env:USERPROFILE` (the template stores it XML-escaped as `&lt;USER_HOME&gt;`, which a plain text replace misses), fills `<PROJECT_DIR>` in `bin\bb-launch.ps1`, saves the XML as UTF-16 and registers the task. It stops with `TASK-INSTALL-FAIL` and exit 1 if any placeholder is left in the XML before registering or in the registered task (read back with `schtasks /Query /XML`). Pass is `TASK-INSTALL-OK`. Tested on one Windows 11 PC with Windows PowerShell 5.1 and Grok Build, the installer printed TASK-INSTALL-OK (exit 0); the launch task ran with result 0; the already-running guard opened no tab while a Build tab was open; after that tab was closed with `bb-off`, it opened exactly one new tab. Start: `schtasks /Run /TN "Build Bridge Launch"`.

## Known issue
- The launcher does not start the outbox and reply watchers; run `bb-on.ps1` after launch.

## Check
- Windows: `schtasks /Query /TN "Build Bridge Launch" /XML` shows `<Triggers />`. Run it twice: first prints LAUNCHED (one tab), second does nothing (ALREADY-RUNNING in the script, IgnoreNew in the task).

## Undo
- Windows: `schtasks /Delete /TN "Build Bridge Launch" /F`, then move `bin\bb-launch.ps1`, `bin\bb-build-tab.ps1`, `bin\install-launch-task.ps1` and the XML to `*-removed-<stamp>`.
Undo check: the scan shows `task-build-bridge-launch: False`.
