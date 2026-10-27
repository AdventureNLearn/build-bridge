# Build Bridge changelog

## v1.0.1 (2026-10-26)
- Step 7 fix (affects v1.0.0 too): in a live soak the registered "Build Bridge Launch" task kept a literal `<USER_HOME>` in its action path, so every task run failed (0xFFFD0000) and auto-pickup logged TAB-NOT-SEEN. The template stores the placeholder XML-escaped (`&lt;USER_HOME&gt;`), which the documented replace step missed. Filling the real path by hand fixed it (the task then returned 0x0 and a test job was picked up and replied to in about a minute). v1.0.1 adds `install-launch-task.ps1`, which fills `<USER_HOME>` (raw and escaped form) from `$env:USERPROFILE` and `<PROJECT_DIR>` in `bb-launch.ps1`, and stops with exit 1 if any `<...>` placeholder is left in the task XML before registering or in the registered task (read back with `schtasks /Query /XML`). The launcher SKILL and card now use it. Tested on a PC: on one Windows 11 PC with Windows PowerShell 5.1 and Grok Build, the installer printed TASK-INSTALL-OK (exit 0); the launch task ran with result 0; the already-running guard opened no tab while a Build tab was open; after that tab was closed with `bb-off`, it opened exactly one new tab. v1.0.0 files are unchanged and still have the bug.
- Keygen fix: `bb-keygen.ps1` now also removes the explicit SYSTEM (`*S-1-5-18`) and Administrators (`*S-1-5-32-544`) entries, and any other non-owner entry, from the key folder. `/inheritance:r` alone kept them on a normal PC, so the owner-only check stopped keygen. The fix runs only on an EMPTY key folder; a non-empty folder or an existing key stops (exit 3) and nothing is changed, overwritten or deleted. Tell the person.
- Keygen (9072ed42): checks the key folder for ANY entry with `[System.IO.Directory]::GetFileSystemEntries` on the resolved path, before any write, and stops with exit 3. Passed a test-mode run on Windows PowerShell 5.1 (empty folder, folder with one unrelated file, re-run with key present); an earlier reported failure was withdrawn (setup used the v1.0.0 keygen).
- The same owner-only logic now applies where `auto-hmac.key` (`Set-BBOwnerOnlyAcl` in `bb-common.ps1`) and `webhook.json` (`bb-set-webhook.ps1`, now created empty, locked and verified before the secret is written) are written. `Test-BBOwnerOnlyAcl` is unchanged.
- PC results: one live run on one Windows 11 PC (PowerShell 5.1, Grok Build 1.0.70) passed the steps in TEST-LOG.md (keygen was fixed by hand in that run). On Windows PowerShell 5.1 in test mode, the ACL case (A) passed on keygen b5da8cf8, and keygen 9072ed42 then passed all three cases (A, B, re-run A).
- PC staging in test mode (PS 5.1, fake values): bb-set-webhook refused an http URL (exit 1, nothing saved); a fake https URL gave WEBHOOK-SAVED with webhook.json owner-only; New-BBAutoKey created auto-hmac.key owner-only and a second call was idempotent; the live-folder guard gave TEST-REFUSED exit 4. The webhook.json and auto-hmac.key write paths passed in test mode only.
- Live soak: a one-hour live soak passed on one Windows 11 PC (PowerShell 5.1) with auto-pickup off: 41 of 41 signed jobs done, bad jobs rejected. See TEST-LOG.md.
- Longer soaks, auto-pickup and the rest stay [UNTESTED]: macOS/Linux, autopickup and 4c auto mode, mid-session idle pickup, sign-out/sign-in, soaks longer than one hour, multiple PCs.
- Known issues (not fixed, cause not clear from the code): `bb-off` printed exit code -1 although status showed every line off; on a first launch, a manual `bb-launch` right after `schtasks /Run` printed LAUNCHED while only one tab existed. See TEST-LOG.md.
- Known issue: The launcher does not start the outbox and reply watchers; run `bb-on.ps1` after launch.
- Known issue, later fix: ExecutionPolicy Bypass: `bb-launch.ps1` and the watchers and scan cards still run PowerShell with `-ExecutionPolicy Bypass` for that one process. This is a known issue, kept as-is in v1.0.1, to be fixed in a later version.
- Step 0 still downloads the repo archive (main.zip) and checks it against the FINGERPRINTS.txt inside it, `.gitattributes` included. The v1.0.0 release assets are unchanged and stay at tag v1.0.0 for older template users.

## r35 (2026-10-26)
- Known gap: Scripts do not give child processes a minimal environment; child processes inherit the user's environment.

## First release (2026-10-25)
The first public version.
- Windows only. Install files only.
- Never push or publish: the AGENTS.md startup block tells Build never to run git push, publish, upload or release anything, and to stop and ask instead. This is a written rule, not a technical lock.
- Removal saves a copy of AGENTS.md, removes only the Build Bridge section, and stops without changing anything if the section markers are wrong. It asks for a typed `DELETE-KEYS` and, separately, `DELETE-SCANS` before deleting those folders.
- Support: provided as is, no support, use at your own risk.

## Limits
- Superseded by v1.0.1: see TEST-LOG.md for the one PC run.
- Not tested yet: Build itself starting and finishing a job with no one at the PC, and whether Build enforces its deny list.
