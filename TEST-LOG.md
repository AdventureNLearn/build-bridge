# Build Bridge test log

## Live run, release v1.0.0
One PC, one run: Windows 11, Windows PowerShell 5.1, Grok Build 1.0.70.

- Fingerprint check: printed `FINGERPRINTS-OK 42 files`.
- Step 2: FOLDERS-OK.
- Step 3: keygen first STOPPED on the owner-only check (SYSTEM and Administrators entries stayed after `/inheritance:r`). Worked after a manual fix: KEYGEN-OK owner-only=True. v1.0.1 puts that fix in `bb-keygen.ps1`; it passed the separate v1.0.1 run below.
- Step 4: scripts copied, hashes match. The person saved the webhook themselves; webhook.json is owner-only.
- Step 5: on/status/off work. Outbound and reply watchers ran. A malformed unsigned job was rejected (BAD_FIELD) within 10 s.
- Step 6: RULE-ADDED (no AGENTS.md before; a marker was written). CheckOnly: CHECK-OK.
- Step 7: task created, no triggers, IgnoreNew. Second launch: ALREADY-RUNNING, one tab only. (Windows doesn't show the RunLevel line when it is at the default LeastPrivilege.)
- Step 8: self-test PASS signed-accepted / unsigned-rejected / tampered-rejected.
- Round trip: a signed job was picked up by an open Build session (launcher start prompt) in about 45 s, moved to done once, a reply was written, the reply watcher got WEBHOOK 200, and the bot woke. autopickup was off (SKIP autopickup-off).

## v1.0.1 PC result (keygen 9072ed42, bb-common 2fa157d9)
Windows PowerShell 5.1, test mode (BB_TEST=1, BB_HOME set to a test folder).
- Earlier run on keygen b5da8cf8: case A (ACL) PASS. Its case B FAIL is withdrawn: that run used the v1.0.0 keygen due to a test setup error.
- A. Empty key folder that inherited the default Windows group entries: KEYGEN-OK owner-only=True, owner account only. PASS.
- B. Key folder holding one unrelated file: KEYS-FOLDER-NOT-EMPTY STOP, exit 3, nothing written, permissions untouched. PASS.
- Re-run of A with the key present: KEY-EXISTS STOP, exit 3. PASS.

## v1.0.1 PC staging, write paths (test mode, fake values)
Windows PowerShell 5.1, test mode (BB_TEST=1, BB_HOME set to a test folder). Only fake values were used.
- bb-set-webhook.ps1 with an http URL: refused, exit 1, nothing saved. PASS.
- bb-set-webhook.ps1 with a fake https URL: WEBHOOK-SAVED, and webhook.json was owner-only. PASS.
- New-BBAutoKey: created auto-hmac.key owner-only. A second call was idempotent. PASS.
- Live-folder guard: TEST-REFUSED, exit 4. PASS.
- The webhook.json and auto-hmac.key write paths passed in test mode only. (A separate one-hour live soak is in the next section.)

## Live soak, one hour
One Windows 11 PC, Windows PowerShell 5.1, one hour. Results come from the soak run's own report (the soak output files are not in this repo).

- The soak ran on the scripts from the v1.0.1 build zip 7fbd89cf (the scripts are identical in the current build); `bb-common.ps1` and `bb-set-webhook.ps1` matched the scripts in this repo.
- Auto-pickup was off during the soak. Auto-pickup was not tested.
- Grok Build version: [UNKNOWN].
- 41 of 41 signed jobs reached done.
- Unsigned, tampered and malformed jobs were rejected.
- A duplicate job id was refused at signing.
- Throughput: about 8.7 jobs per 10 minutes overall, and 10.4 per 10 minutes under stress.
- Swarm jobs used 10, 20, 26 and 6 helpers. Coverage was 9/10, 20/20, 28/30 and 20/20.
- No errors in the logs. Wake pings were batched, and all returned HTTP 200.
- Not covered by this soak: longer soaks, auto-pickup and the rest stay [UNTESTED] (see the list below).

## Live soak finding: step 7 task path (affects v1.0.0 and v1.0.1 docs)
- The installed "Build Bridge Launch" scheduled task kept the literal `<USER_HOME>` in its action path (the template stores it XML-escaped, so the documented replace missed it). Every task run failed with 0xFFFD0000 and auto-pickup logged TAB-NOT-SEEN.
- Fixed by hand on the PC by filling the real home path: the task then returned 0x0, and a test job was picked up and replied to in about a minute.
- v1.0.1 adds `install-launch-task.ps1`, which fills the placeholders and fails (exit 1) if any `<...>` placeholder remains in the XML before registering or in the registered task. Tested on a PC: on one Windows 11 PC with Windows PowerShell 5.1 and Grok Build, the installer printed TASK-INSTALL-OK (exit 0); the launch task ran with result 0; the already-running guard opened no tab while a Build tab was open; after that tab was closed with `bb-off`, it opened exactly one new tab.
- v1.0.0 step 7 has the same bug; the v1.0.0 files stay unchanged.

## Known issues
- `bb-off` printed an odd exit code -1, but status showed every line off. Cause [UNKNOWN]; not clear from the code, so not changed.
- On the first launch, a manual `bb-launch` right after `schtasks /Run` printed LAUNCHED, but only one tab existed. Cause [UNKNOWN] (a race between the task's launch and the manual one is possible but not proven); not changed.
- Build output and replies can include local paths, such as the user folder and project folder. Check output before sharing it.
- In swarm jobs, the main session merges and checks the parts instead of separate lead and checker helpers.
- The pickup and returned stamps are identical, and a job can reach done before its reply is written.
- A driver double-start had no effect.
- The launcher does not start the outbox and reply watchers; run `bb-on.ps1` after launch.
- ExecutionPolicy Bypass: `bb-launch.ps1` and the watchers and scan cards still run PowerShell with `-ExecutionPolicy Bypass` for that one process. This is a known issue, kept as-is in v1.0.1, to be fixed in a later version.

## [UNTESTED]
Longer soaks, auto-pickup and the rest stay [UNTESTED]: macOS/Linux, autopickup and 4c auto mode, mid-session idle pickup, sign-out/sign-in, multiple PCs, any soak longer than one hour.
