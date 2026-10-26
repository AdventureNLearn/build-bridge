---
name: build-bridge-startup-rule
description: 'Step 6 of Build Bridge: add the Build Bridge block to the project AGENTS.md so each Build session turns its listener on at start and off at exit. Use for step 6 and its undo.'
---

# Build Bridge, step 6: Build startup rule

## Purpose
Add a marked block to the project AGENTS.md so each Build session turns its listener on at start and off at exit.

## Steps

Ask: "Step 6 adds a short marked block to `<PROJECT_DIR>/AGENTS.md`, after saving a backup. The block tells each Build session to turn its own listener on at start, act only on signed jobs, and turn the listener off at exit. Reply YES." Wait for YES.

Important: a Build session does not act on AGENTS.md until it gets its first message. The rule alone never starts the listener. The launcher's starting prompt (`bb-build-tab.ps1`) is that first message, and it says the same thing: turn the listener on, then check the outbox. A session that someone opens by hand starts listening only after the person's first message.

Do it (first copy this folder into `<USER_HOME>/.buildbridge/bin/`, so the rollback drill can find the undo):
- `add-startup-rule.ps1 -ProjectDir "<PROJECT_DIR>"`.
The script copies AGENTS.md to `AGENTS.md.buildbridge-backup-<stamp>` (or writes a `.buildbridge-none` marker if there was no AGENTS.md), then appends `startup-rule-block.md`. It refuses to run if the block is already there.

## Check
It prints `RULE-ADDED`. The scan then shows `agents-md-has-bb-block: True`.

## Undo
`remove-startup-rule.ps1` first checks the markers (`-CheckOnly` runs only this check, changes nothing and prints CHECK-OK or STOP; the rollback runs it before anything else and halts with exit 7 on a STOP); if they are missing, duplicated, out of order or changed it STOPs (exit 3) and changes or deletes nothing. Otherwise it saves AGENTS.md aside as `AGENTS.md.before-bb-remove-<stamp>` and prints where, removes only the lines from `<!-- BEGIN BUILD BRIDGE -->` through `<!-- END BUILD BRIDGE -->` (every other line and byte kept), deletes AGENTS.md only if Build Bridge created it and it is empty (empty means only blank lines or spaces are left), then deletes the install-time backup or marker. It never copies the pre-install backup over AGENTS.md. It prints `SAVED-ASIDE <path>`, then `RULE-REMOVED` or `AGENTS-MD-DELETED`, then `INSTALL-COPY-DELETED <name>`; a STOP prints `STOP: <why>`. Undo check: the scan shows no Build Bridge block in AGENTS.md (`agents-md-has-bb-block: False`, or AGENTS.md absent if Build Bridge created it and it was deleted). If Build Bridge created AGENTS.md and the person added lines, the file stays, so the rescan shows `agents-md-exists` differing from scan-1.
