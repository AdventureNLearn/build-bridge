---
name: build-bridge-test-and-rollback
description: 'Step 8 of Build Bridge: run the test plan, list every change with its undo, and run the rollback drill whose final scan must match the step-1 scan. Use for step 8 and whenever the owner wants everything removed.'
---

# Build Bridge, step 8: test, summary and rollback drill

## Purpose
Run the self-test, show every change with its undo, and run the rollback drill, whose final scan must match the step 1 scan.

## Steps

Ask: "Step 8 runs a short self-test. It drops one signed, one unsigned and one tampered test job in your outbox and watches what happens. Nothing else changes. Reply YES." Wait for YES.

### Self-test
- `bb-selftest.ps1`.
- It needs the watchers on (build-bridge-controls `on`) and Build off, or Build on if you also want the full round trip.
- Pass lines: `PASS signed-accepted`, `PASS unsigned-rejected`, `PASS tampered-rejected`. The test ids start with `BB-SELFTEST-`. Undo: the script moves its own test files to `rejected/` or `done/`, so nothing is left in the outbox.

Live checks for the test log. Run them by hand on Windows and write each result as PASS, FAIL or NOT CHECKED:
1. One signed job goes out, Build runs it, and it moves to `done/`.
2. One reply comes back, and Grok Bot gets exactly one wake ping (`logs/watch-inbox.log` shows one `WEBHOOK 2xx`). The ping body is only `{"event":"ACTION_REQUIRED","source":"buildbridge"}`.
3. Unsigned and tampered jobs land in `rejected/` (self-test).
4. With the watchers off, a new job stays in `outbox/` and no wake line is written.
5. With Build running, remote start prints ALREADY-RUNNING and opens no second tab.
6. After `off`, status shows every line `off`, and no Build Bridge tab is left open.
7. (not tested) After signing out and back in, status shows every line `off`.
8. The rollback drill below passes.
9. KNOWN ISSUE (not tested): with an open, idle Build session, drop a signed job, then send Build any message. It must pick the job up on that turn. With autopickup on, `logs/pickup.log` must show `QUEUED` (the QUEUED part was tested in an earlier revision in test mode; Build picking the job up is (not tested)).
10. (not tested): with Build closed and autopickup on, one signed job opens exactly one run (`START`). A second job arriving during that run must not open a second one.

### Home isolation and test mode
- Every script takes its root from `BB_HOME`. When `BB_HOME` is unset, the root is `<USER_HOME>\.buildbridge`. The keys folder is always next to the root, as `<root>-keys`.
- Test mode is `BB_TEST=1`. In test mode every script (scan, status, self-test, rollback and the rest) refuses to run, with exit 4 and `TEST-REFUSED`, unless `BB_HOME` is set to a folder other than the live `<USER_HOME>\.buildbridge`. It never falls back to the live profile. In test mode the rollback also skips the live task.
- Example (PowerShell): `$env:BB_TEST = "1"; $env:BB_HOME = "<TEST_DIR>\.buildbridge"`, then `bb-selftest.ps1`.

### Windows PowerShell 5.1
- Earlier revisions had a test-mode run on one Windows PC. This version is tested on the author's box only; no Windows PC staging run or soak has been done. The earlier run used Windows PowerShell 5.1 in test mode, including the watchers round trip and hands-off pickup without Build doing a job. Build itself starting and finishing a job, and whether Build enforces its deny list, are not tested yet.

## Check
The self-test pass lines below, the live checks, and `SCAN-MATCH` at the end of the rollback drill.

### Summary of changes (show this to the person)
| Step | Change | Undo |
|---|---|---|
| 2 | `<USER_HOME>\.buildbridge` | undo-folders |
| 3 | `<USER_HOME>\.buildbridge-keys`, public key | undo-keys; the rollback can delete the keys folder only after DELETE-KEYS |
| 4 | watcher scripts, webhook file, autopickup flag | off, `bb-pickup -Disable`, then move aside |
| 5 | on/off/status | move aside |
| 6 | AGENTS.md block | remove-startup-rule |
| 7 | Task Scheduler task | unregister, then move aside |

## Undo: rollback drill
Ask: "This undoes every step in reverse order. First the undo steps run. Before it stops, removes or moves anything, the rollback checks the AGENTS.md markers (`remove-startup-rule.ps1 -CheckOnly`). If the check STOPs, it prints `ROLLBACK-HALTED`, exits 7 and changes nothing. Without any typed word it deletes only the scheduled task, the Build Bridge block in AGENTS.md (after saving AGENTS.md aside), an empty AGENTS.md that Build Bridge created, the install-time backup or marker, and with `-Rescan` an existing `scan-2.txt` (full list: DISCLOSURE.md, How to remove it). Everything else is moved aside. Then the script asks two separate questions, each with its own typed YES word: DELETE-KEYS deletes the one moved-aside keys folder (private key, webhook.json, auto-hmac.key), and DELETE-SCANS suggests deleting `<root>-scans`, a snapshot of your PC that includes the startup list. Reply YES to start the rollback." Wait for YES.
- Deletes (Windows `bb-rollback.ps1` only): after the moves (and the rescan, if given), it asks `DELETE-KEYS` for the one keys folder `<root>-keys-removed-<stamp>`, then, separately, `DELETE-SCANS` for `<root>-scans`, suggesting it be deleted because it is a snapshot of the PC, including the startup list. Only the exact typed word counts. With no YES, any other answer, or no console to ask (input redirected), that folder is not deleted and the script prints where it still is (`KEYS KEPT at: <path>`, `SCANS KEPT at: <path>`). On a YES it prints `DELETE-KEYS done: <path>` / `DELETE-SCANS done: <path>`, or `... FAILED` with the path if the folder is still there.
- `bb-rollback.ps1 -ProjectDir "<PROJECT_DIR>"`.
- Run the scan from the package or a temp copy (never from `.buildbridge/bin`, which the rollback moves aside). Scan-1 must already be saved (step 1 with `-Save 1`) in `<root>-scans/`, which the rollback does not move.
- `-Rescan` accepts ONLY the package's own scan script: the full path must be `build-bridge-scan\scan.ps1` in the same package, or the scan script beside the rollback script. If the package `MANIFEST.md` lists it, its sha256 must match. Anything else gives `RESCAN-REFUSED` (exit 6) before any undo step runs.
- Easiest: give the rollback the scan path. `bb-rollback.ps1 -ProjectDir "<PROJECT_DIR>" -Rescan <path to scan.ps1>`. After the undo steps it runs the scan with save 2, which writes `<root>-scans/scan-2.txt`, compares it with scan-1 and prints `SCAN-MATCH` or `SCAN-DIFF`. Have Build in the same state it was in at step 1. By hand, the same is `scan.ps1 -ProjectDir "<PROJECT_DIR>" -Save 2`; `compare-scan.ps1 -Baseline <scan-1> -After <scan-2>` still works. Pass = `SCAN-MATCH`.
- Step 7 in test mode (`BB_TEST=1`): the test launcher name is REQUIRED and has no default. It is `BB_TASK_NAME`. Set it to the exact name the test registered. The name must contain "test", must not be the live name (`Build Bridge Launch`). Otherwise the rollback prints `UNDO-7 REFUSED`. The same name and guard are used by `on -WithBuild`, by the pickup launcher fallback and by the scan, so in test mode nothing starts, queries or removes the live launcher. Check: the output names the test task, and the live one is still registered. Undo of this undo: re-register the test task from its file (step 7).
- The other `*-removed-<stamp>` folders (the jobs folder and anything else moved aside) are not deleted by the rollback; deleting them is a separate step that needs its own YES. To look for them, use `Get-ChildItem -Force <USER_HOME>`: the moved-aside jobs folder keeps its Hidden flag, so a plain `Get-ChildItem` does not list it.
