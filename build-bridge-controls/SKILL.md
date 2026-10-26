---
name: build-bridge-controls
description: 'Step 5 of Build Bridge: on, off and status commands, including a clean shutdown that closes the Build tab. Use for step 5 and whenever the owner asks to turn Build Bridge on or off or check it.'
---

# Build Bridge, step 5: on, off and status

## Purpose
Add on, off and status commands, with a clean shutdown that also closes the Build tab.

## Steps

Ask: "Step 5 adds three commands, on, off and status. Nothing starts at sign-in. On Windows these scripts run with `-ExecutionPolicy Bypass`. That flag only lets PowerShell run these script files for that one run. It changes no system setting and does not turn off any of Build's approvals. Reply YES." Wait for YES.

Install: copy into `<USER_HOME>/.buildbridge/bin/` and replace `<PROJECT_DIR>` in `bb-status`/`bb-off` with the person's Build project folder (from the scan).
| | Windows |
|---|---|
| On | `bb-on.ps1` (`-WithBuild` also starts Build) |
| Off | `bb-off.ps1` |
| Status | `bb-status.ps1` |
Run them through Grok Bot's computer tool on the person's machine: `powershell -NoProfile -ExecutionPolicy Bypass -File <USER_HOME>\.buildbridge\bin\bb-on.ps1`. No desktop shortcuts are needed. Make shortcuts only if the person asks, and never in a Startup folder.

**Off** stops, in this order: both watchers, the listener, the Build session whose command line has `--cwd <PROJECT_DIR>`, and then the tab host. It matches only processes owned by this user (same session and owner), and only by the full installed path `<USER_HOME>\.buildbridge\bin\bb-...` or `grok --cwd <PROJECT_DIR>`. A copy of the same script somewhere else, or another user's Build Bridge, is never counted or stopped. Status and the scan use the same matching. Not tested on Windows.

**Leftover-tab fix** (not yet tested live; this is the design):
- Cause: Build was the tab's own process, so a forced stop exited non-zero and Windows Terminal kept a dead "process exited" tab.
- Fix: the launcher runs Build inside a small host script (`bb-build-tab.ps1`, in build-bridge-launcher) that always exits 0 after Build ends. Off ends Build first and the host exits cleanly.
  - Windows Terminal: a tab closes on exit 0 under the default `closeOnExit`. (not tested)
- If the host is still alive after 3 s, off force-stops it and reports `tab-host-forced: True`. Tell the person that one tab may need closing by hand. Never close other tabs or windows.

## Check
After `off`, status shows every line `off` and the tab is gone. After `on`, both watchers show `on`.
## Undo
Run `off`, then move `bin/bb-on*`, `bin/bb-off*` and `bin/bb-status*` to `*-removed-<stamp>`.
