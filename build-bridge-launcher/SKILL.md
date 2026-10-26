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

Files (copy to `<USER_HOME>\.buildbridge\bin\`, then replace `<PROJECT_DIR>` and `<USER_HOME>`):
| | Windows |
|---|---|
| Launcher | `bb-launch.ps1` |
| Tab host (exits 0 so the tab closes) | `bb-build-tab.ps1` |
| On-demand job | `build-bridge-launch.task.xml` (Task Scheduler, `<Triggers />`, LeastPrivilege) |

The starting prompt lives in the tab host. It tells the new session to turn on the listener and check the outbox right away, because a Build session does not act on the AGENTS.md startup rule until it gets its first message (see build-bridge-startup-rule).

The tab host sets `BB_LAUNCHED=1` before starting Build, so allow-auto refuses inside a launched session. See build-bridge-watchers step 4c for the YES, the undo and the check.

Do it (no admin rights, per-user only; setup locks your own keys folder with icacls in step 3):
- Windows: save the XML as UTF-16, then `schtasks /Create /TN "Build Bridge Launch" /XML "<USER_HOME>\.buildbridge\bin\build-bridge-launch.task.xml"`. Start: `schtasks /Run /TN "Build Bridge Launch"`.

## Check
- Windows: `schtasks /Query /TN "Build Bridge Launch" /XML` shows `<Triggers />`. Run it twice: first prints LAUNCHED (one tab), second does nothing (ALREADY-RUNNING in the script, IgnoreNew in the task).

## Undo
- Windows: `schtasks /Delete /TN "Build Bridge Launch" /F`, then move `bin\bb-launch.ps1`, `bin\bb-build-tab.ps1` and the XML to `*-removed-<stamp>`.
Undo check: the scan shows `task-build-bridge-launch: False`.
