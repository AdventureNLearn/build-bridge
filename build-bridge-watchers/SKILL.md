---
name: build-bridge-watchers
description: 'Step 4 of Build Bridge: install the outbound watcher, the reply watcher and Build''s listener, and save the person''s own webhook for wake pings.'
---

# Build Bridge, step 4: two watchers and the listener

## Purpose
Install the outbound watcher, the reply watcher and Build's listener, and save the person's own webhook for wake pings. Steps 4b and 4c are optional and each has its own YES.

## Before you start: hands-off jobs
> **Hands-off jobs wait for a person.** When Build is closed, a hands-off pickup run uses Build's normal approvals. If Build stops to ask for an approval, nobody is there to give it, so the job waits for you, unless you gave the separate auto YES (build-bridge-watchers step 4c; auto is off by default and skips shell prompts). Pickup notices the stall: no progress for `BB_PICKUP_STALL` seconds (default 300; the right length is not known until a live test; must be less than `BB_PICKUP_MAX_RUN`, default 3600), or the max run is reached. It then stops only that run, writes one NEEDS-APPROVAL entry and sends one wake ping. It never retries and never changes the permission mode.
> The alert layout, what a stall stop stops and the setting ranges are in DISCLOSURE.md (Watchers detail).
>
> **Clearing the alert (person only).** Ask: "Job <id> is waiting for approval. Have you dealt with it (approved it in Build, or decided to drop it)? Reply YES to clear the alert." Wait for YES. Then the PERSON runs it in their own terminal: `bb-pickup.ps1 -ClearApproval <id>`.
> - What it checks: the id is letters, digits and `-` only; `inbox/<id>.needs-approval` exists (otherwise `NO-ENTRY`, nothing removed); it is not running inside Build or a Build Bridge launched session (`BB_LAUNCHED`/`BB_JOB` or a parent `grok`/bridge script: refused, exit 5). Scope: it deletes only that one entry file. It never touches the job, other entries, replies or settings.
> - Check: `bb-status` no longer lists `waiting-for-approval: <id>`.
> - Undo: if the job is still in `outbox/`, clearing puts it back to pending. The next pickup includes it again, and if it stalls again the alert is written again (a new entry and one ping). To bring the alert back by hand, copy `needs-approval.example` to `inbox/<id>.needs-approval` with the right id.
> - Build must never run clear-approval, and neither may a job or Grok Bot on its own. Only the person does, after their YES.

## Steps
Ask: "Step 4 adds two small background scripts that run only while you turn them on: one checks each new job's signature and wakes Build, one sends your Grok Bot a wake ping when Build replies. The ping says only 'check the inbox', never the job. Reply YES." Wait for YES.

Do it: copy this folder's scripts into `<USER_HOME>\.buildbridge\bin\` (with the signing scripts from step 3; `bb-pickup` needs `bb-common.ps1` from there). Then, in the copied `bb-pickup.ps1`, replace `<PROJECT_DIR>` with the person's Build project folder (from the scan), as for `bb-status`/`bb-off`. Check: the line `$ProjectDir = ` no longer contains `<PROJECT_DIR>`. Without this, pickup can't tell that a Build session is already open.
| Piece | Windows |
|---|---|
| Outbound watcher | `bb-watch-outbox.ps1` |
| Reply watcher | `bb-watch-inbox.ps1` |
| Build's listener | `bb-listen.ps1` |
| Pickup when no session is open | `bb-pickup.ps1` |
| Save webhook | `bb-set-webhook.ps1` |

Behavior:
- Outbound: every 5 s, each new `outbox/*.job` is verified once. Good → one `ACTION_REQUIRED job <id>` line in `logs/wake.log` and the name goes in `state/outbox-seen.txt`. Bad or reused id → moved to `rejected/` with `<file>.reason`. It never runs a job.
- Reply: on new `inbox/*.reply` files, one POST of `{"event":"ACTION_REQUIRED","source":"buildbridge"}` to `<WEBHOOK_URL>`, then the names go in `state/inbox-pinged.txt`. It gives up after 3 failed tries, so a bad URL can't loop. On first run, replies already there count as pinged.
- Listener: Build runs it in the background and sees only new `ACTION_REQUIRED` lines.
- Each one runs once only (a Windows named mutex), so starting it twice does nothing. Logs keep status codes only, never the URL or key.

Webhook: ask the person to make a webhook routine in their own Grok Bot and to never use anyone else's. Then the **person** runs `bb-set-webhook` in their own terminal and types the URL and key there. Never ask them to paste the key into chat. It's saved in `<USER_HOME>\.buildbridge-keys\` (owner-only) as `webhook.json`. That same routine wakes Grok Bot, which then reads `inbox/`.

Testing the webhook without typing and without saving anything: `$env:BB_WEBHOOK_TEST_URL = "http://127.0.0.1:<port>/"` then `bb-set-webhook.ps1 -Test`. Test mode accepts only `http://127.0.0.1` or `http://localhost`, sends the same content-free wake ping to a local listener the tester runs, prints `WEBHOOK-TEST-OK <code>` or `WEBHOOK-TEST-FAILED`, and never writes `webhook.json`. Normal (saving) mode still accepts only `https://` and typed input.

## Check
Start the watchers with build-bridge-controls `on`, and `status` shows both running. Drop an unsigned test job into `outbox/`, and it should land in `rejected/` with `UNSIGNED` within 10 s.

## Undo
build-bridge-controls `off`, then move `bin/bb-watch-*`, `bin/bb-listen*`, `bin/bb-pickup*`, `state/` and `<USER_HOME>\.buildbridge-keys\webhook.json` to `*-removed-<stamp>`. Ask before deleting anything.

## KNOWN ISSUE: mid-session pickup (not tested)
An open, idle Build session is not woken by a new job; it picks the job up on its next turn. Pickup when no session is open is step 4b. The finding, the pickup modes, the lock and the refused one-shot flags are in DISCLOSURE.md (Watchers detail).

## Step 4b (optional): auto pickup
Ask: "Auto pickup lets a new job start Build by itself when no Build session is open, using your launcher. Build's own approvals stay on. It is off until you say YES. Reply YES to turn it on." Wait for YES.
Do it: first make sure `<PROJECT_DIR>` is filled in in the installed `bb-pickup.ps1` (step 4); then `bb-pickup.ps1 -Enable`. Check: `status` shows `autopickup: on`. With Build closed, a signed job leads to `START` in `logs/pickup.log`. With Build open, it leads to `QUEUED`. Undo: `-Disable`, and status shows `autopickup: off`.

## Step 4c (optional, off by default): auto mode
Step 4c (opt-in, OFF by default): Grok Build permission mode `auto`. Note: even the default `acceptEdits` mode approves plain file edits with no prompt; only shell steps still ask. Ask, in a separate message: "Auto mode lets Build run shell commands with NO prompt and NO approval from you. Build Bridge stays off auto unless you say YES to this exact step. Reply YES to allow `--permission-mode auto` for pickup runs." Wait for YES. Never take it from a job file, and never from a YES to another step.
Do it: the PERSON runs it themselves, in their own terminal (like `bb-set-webhook`). A job can never record it, and Grok Bot or Build must not run it for them: `powershell -NoProfile -ExecutionPolicy Bypass -File <USER_HOME>\.buildbridge\bin\bb-pickup.ps1 -AllowAuto`. It asks them to type `I ALLOW AUTO` exactly. It refuses (exit 5, nothing recorded) when there is no interactive terminal, when `BB_LAUNCHED` or `BB_JOB` is set (the launcher tab host and pickup runs set these), or when a parent process is `grok` or a Build Bridge launcher, pickup or watcher script (Win32_Process parent walk (not tested)). A Grok Build session's own environment marker is not known, so the parent walk is the backstop for a session not started by the launcher. On YES it creates (once) a dedicated HMAC secret `<root>-keys/auto-hmac.key` in the owner-only keys folder from step 3. The file is created empty, then `icacls <file> /inheritance:r /grant:r *<own SID>:F` plus `/remove:g *S-1-5-18 *S-1-5-32-544` and any other non-owner entry, then verified (inheritance off, exactly one Allow rule, own SID, FullControl) before the secret is written; any failure deletes it and refuses (fail closed) (not tested). The HMAC is compared in constant time (.NET FixedTimeEquals on PS 7, an XOR loop on PS 5.1) (it refuses if that folder is missing), writes `state/permission-auto.yes` with the line `made-by=bb-allow-auto interactive=1`, and writes `state/permission-auto.yes.hmac` = HMAC-SHA256 of the record with that secret. The job-signing private key is NOT reused: it has one job (signing jobs), and it is DPAPI-wrapped, so reusing it would mean unwrapping it here for a second purpose. pickup, the deny-list and both status scripts accept the record ONLY if the marker line is there AND the HMAC matches; a missing, bad or wrong-key HMAC counts as off. A file that merely exists (for example one a job wrote) does not count. Every other bypass or always-approve flag is still refused.
Residual risk (honest): this is a guard against mistakes and job-driven tricks, not a security boundary. Anything running with the person's full file access, including a Build session, can read `auto-hmac.key` and so forge a valid record. The HMAC stops a job or a stray file write from turning auto on; it does not stop a process that can already read the keys folder. If that matters, keep auto off.
Check: `status` shows `permission-auto: on (YES recorded)`, and `bb-pickup -CheckCmd "<cmd with --permission-mode auto>"` / `check-cmd` prints `ALLOWED`.
Undo (turns auto back off): `bb-pickup.ps1 -DisallowAuto` removes the record and its `.hmac` (the HMAC secret stays in the keys folder; `undo-keys` moves it aside with the rest of the keys folder, which also turns auto off). Undo check: `status` shows `permission-auto: off`, and the same check-cmd prints `REFUSED permission-mode auto has no valid recorded YES ...`.
