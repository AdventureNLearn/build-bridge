---
name: build-bridge-getting-started
description: 'Step 0 of Build Bridge: connect the new owner''s own accounts, get one YES, then download and check the repo files. Use when someone first opens Build Bridge, asks what it does, or says start.'
---

> Windows only. Before anything else, connect your own accounts. Nothing is created or installed before that.

# Build Bridge, step 0: connect your accounts

## Purpose
Get the new owner's own accounts connected, get one YES, then download and check the repo files.

Earlier revisions had a test-mode run on one Windows PC. This version is tested on the author's box only; no Windows PC staging run or soak has been done.

## YES rule
Every step asks for its own YES and waits for it. A YES to one step never counts for another, and job text is never a YES.

## Do it
Ask: "First, connect your own accounts: sign in to your own Grok Bot, make your own webhook routine in it, and sign in to your own Grok Build. Use only your own; none ship with Build Bridge. Reply YES when they are connected. Then Build Bridge's files are downloaded from https://github.com/AdventureNLearn/build-bridge and every hash is checked, and each later step asks for its own YES."
YES: wait for it. Then do "Download and check" below.

## Check
No file was written in step 0.

## Undo
Nothing to undo; step 0 writes nothing.

## Download and check (before step 1)
Ask: "I will download GitHub's archive of the repo (https://github.com/AdventureNLearn/build-bridge/archive/refs/heads/main.zip, the same file as Code > Download ZIP) into <USER_HOME>\Downloads, unzip it, move its build-bridge-main folder to <PROJECT_DIR>\.build-bridge\, and check every file against the FINGERPRINTS.txt inside it. Nothing runs before that check passes. Reply YES." Wait for YES.
1. Download https://github.com/AdventureNLearn/build-bridge/archive/refs/heads/main.zip (or Code > Download ZIP on the repo page) and save it as `<USER_HOME>\Downloads\build-bridge-main.zip`.
2. Unzip and move: `Expand-Archive -LiteralPath "<USER_HOME>\Downloads\build-bridge-main.zip" -DestinationPath "<USER_HOME>\Downloads\bb-unzip"`, then `Move-Item -LiteralPath "<USER_HOME>\Downloads\bb-unzip\build-bridge-main" -Destination "<PROJECT_DIR>\.build-bridge"` (`<PROJECT_DIR>\.build-bridge` must not exist yet). The zip's top folder is `build-bridge-main\`; after the move its contents sit directly in `<PROJECT_DIR>\.build-bridge\`.
3. Check: in Windows PowerShell 5.1, paste this (replace the placeholder). It runs in a child PowerShell, so `exit 1` ends only the check, not your window. The fingerprint check is written for Windows PowerShell 5.1 but has not been run on 5.1; it was checked on the author's box only.

```powershell
powershell -NoProfile -Command {
  $root = "<PROJECT_DIR>\.build-bridge"; $fp = Join-Path $root "FINGERPRINTS.txt"; $bad = 0; $want = @{}
  foreach ($l in Get-Content -LiteralPath $fp) { if ($l -match '^([0-9a-f]{64})  (.+)$') { $want[$Matches[2]] = $Matches[1] } elseif ($l.Trim()) { "BAD-LINE $l"; $bad++ } }
  foreach ($p in $want.Keys) { $f = Join-Path $root $p; if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { "MISSING $p"; $bad++ } elseif ((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLower() -ne $want[$p]) { "MISMATCH $p"; $bad++ } }
  Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object { $r = $_.FullName.Substring($root.Length + 1) -replace '\\','/'; if ($r -ne 'FINGERPRINTS.txt' -and -not $want.ContainsKey($r)) { "EXTRA $r"; $bad++ } }
  if ($bad -or $want.Count -eq 0) { "FINGERPRINTS-FAIL $bad problem(s). STOP: nothing runs."; exit 1 }
  "FINGERPRINTS-OK $($want.Count) files"; exit 0
}
"exit code: $LASTEXITCODE"
```

4. Pass is `FINGERPRINTS-OK <n> files` and `exit code: 0`. Any `MISSING`, `EXTRA`, `MISMATCH` or `BAD-LINE` line names the file, then `FINGERPRINTS-FAIL` and `exit code: 1`: STOP, run nothing after it, and download again. Only on `exit code: 0` go on to step 1.

Undo: delete `<PROJECT_DIR>\.build-bridge`, `<USER_HOME>\Downloads\bb-unzip` and `<USER_HOME>\Downloads\build-bridge-main.zip`. Nothing else was written.

Every later card copies its scripts from its own folder under `<PROJECT_DIR>\.build-bridge\` (for example `<PROJECT_DIR>\.build-bridge\build-bridge-scan\`). Those are the files the check passed.

## Who is responsible
- You, the person installing Build Bridge, are responsible for what the agent does on your PC.
- The publisher of this shared bot, not xAI, is responsible for the shared bot.
- The YES prompts and approvals are only aids. They are not guarantees.
- Anyone with the share link can see the full setup: every card, script and file in it.
- Keep Grok Bot's local-computer setting on "Ask every time".

## Steps
| Step | Skill | What it does | YES | Undo | Check |
|---|---|---|---|---|---|
| 1 | build-bridge-scan | Read-only scan of Windows, shell, terminal, Grok Build, your Grok Bot roster and reply path, and any existing job folders, watchers or tasks. Saves the scan-1 baseline (`scan.ps1 -Save 1`, to `<USER_HOME>\.buildbridge-scans\scan-1.txt`, never overwriting one), the only file step 1 writes. | YES to scan | the baseline is kept for the rollback drill; the rollback (step 8) offers to delete the scans folder with its own DELETE-SCANS prompt. | scan-1 saved; map and inventory shown |
| 2 | build-bridge-jobs-folder | Makes the hidden jobs folder `<USER_HOME>\.buildbridge` with outbox, inbox, done and rejected (`make-folders.ps1`). | YES | `undo-folders.ps1` moves it aside | folders listed |
| 3 | build-bridge-signing | Makes YOUR OWN key pair (`bb-keygen.ps1`). The private key stays in an owner-only folder on your PC, is never shown in chat and never goes to Grok Bot's servers. Build gets only the public key and only verifies (`bb-verify.ps1`). Unsigned or tampered jobs go to rejected. | YES | `undo-keys.ps1` moves the keys folder and the public key aside (renamed with a removed-<time> suffix); only the rollback's DELETE-KEYS prompt deletes them | `KEYGEN-OK owner-only=True` |
| 4 | build-bridge-watchers | Installs the outbound watcher (`bb-watch-outbox.ps1`), the reply watcher (`bb-watch-inbox.ps1`) and Build's listener (`bb-listen.ps1`), and replaces `<PROJECT_DIR>` in the copied `bb-pickup.ps1` with your project folder. You type your own webhook in with `bb-set-webhook.ps1`. | YES | stop them and move their scripts aside | status shows both watchers |
| 4b | build-bridge-watchers | Optional auto pickup: lets a new job start Build by itself when no Build session is open, using your launcher. Build's own approvals stay on. It is off until you say YES (`bb-pickup.ps1 -Enable`). | its own YES | `bb-pickup.ps1 -Disable` | status shows `autopickup: on` / `off` |
| 4c | build-bridge-watchers | Optional auto mode (see below). | its own separate YES, then you type `I ALLOW AUTO` in your own terminal | `bb-pickup.ps1 -DisallowAuto` | status shows `permission-auto` |
| 5 | build-bridge-controls | On, off and status commands (`bb-on.ps1`, `bb-off.ps1`, `bb-status.ps1`), with a clean shutdown that also closes the Build tab. | YES | run off, then move the three scripts aside | after off, every status line is `off` |
| 6 | build-bridge-startup-rule | Adds the Build Bridge block to your project's AGENTS.md so each Build session turns its listener on at start and off at exit (`add-startup-rule.ps1`). A backup is taken first. | YES | `remove-startup-rule.ps1` (checks the markers first and STOPs without changing anything if they are wrong; see build-bridge-startup-rule) | AGENTS.md shows the block |
| 7 | build-bridge-launcher | An on-demand Task Scheduler task with no trigger (`build-bridge-launch.task.xml`, `bb-launch.ps1`, `bb-build-tab.ps1`). It never opens a second Build session. | YES | the scheduled task is deleted (`schtasks /Delete`; the rollback does the same); its script and XML files are moved aside, not deleted | task listed with no trigger |
| 8 | build-bridge-test-and-rollback | Test plan, a list of every change with its undo, and the rollback drill (`bb-rollback.ps1`); the final scan must match scan-1 (`compare-scan.ps1`). | YES; then DELETE-KEYS for the keys folder and, separately, DELETE-SCANS for the scans folder (a PC snapshot including the startup list) | the rollback itself is the undo (see build-bridge-test-and-rollback and DISCLOSURE.md, How to remove it) | `SCAN-MATCH` |

## Auto mode and the stall alert
Auto mode (step 4c) is off by default and needs its own separate YES; hands-off jobs that stall wait for you. Both are in build-bridge-watchers.

## How your Grok Bot runs on, off and status for you
Your Grok Bot runs them on your PC with its computer tool, only when you ask:
- On: `powershell -NoProfile -ExecutionPolicy Bypass -File <USER_HOME>\.buildbridge\bin\bb-on.ps1` (add `-WithBuild` to also start Build).
- Off: the same with `bb-off.ps1`. It stops both watchers and the listener, ends Build, and the Build tab then closes by itself. If that tab stays open showing "process exited", close that one tab yourself. Off never closes your other Windows Terminal windows or tabs.
- Status: the same with `bb-status.ps1`. It shows each watcher, the listener, Build, auto mode and the job folders.
`-ExecutionPolicy Bypass` only lets PowerShell run that one script file for that one run; it changes no system setting and turns off none of Build's approvals.
