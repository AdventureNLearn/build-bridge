# Build Bridge: what it does and what you do

Build Bridge is run by an AI assistant (Grok Bot and Grok Build). You approve each step.

File integrity: check every file against FINGERPRINTS.txt.

**Windows only.** Build Bridge has no Mac or Linux scripts.

## What it does

Build Bridge lets your own Grok Bot pass signed jobs to Grok Build on your own Windows PC, using PowerShell scripts, a Task Scheduler task, local files and your own Grok Bot's webhook for wake pings.

One live run on one Windows 11 PC (PowerShell 5.1, Grok Build 1.0.70) passed the steps in TEST-LOG.md. The v1.0.1 keygen fix (bb-keygen.ps1 9072ed42) then passed a separate test-mode run on Windows PowerShell 5.1 (see TEST-LOG.md); the v1.0.1 webhook.json and auto-hmac.key write paths passed in test mode only (PC, PS 5.1); a one-hour live soak passed on one PC with auto-pickup off (see TEST-LOG.md). The step 7 installer (`install-launch-task.ps1`) passed on one Windows 11 PC (PowerShell 5.1): TASK-INSTALL-OK, launch task result 0, and the already-running guard held (see TEST-LOG.md). Longer soaks, auto-pickup and the rest stay [UNTESTED]: macOS/Linux, autopickup and 4c auto mode, mid-session idle pickup, sign-out/sign-in, soaks longer than one hour, multiple PCs.

### Who is responsible
- You, the person installing Build Bridge, are responsible for what the agent does on your PC.
- The publisher of this shared bot, not xAI, is responsible for the shared bot.
- The YES prompts and approvals are only aids. They are not guarantees.
- Anyone with the share link can see the full setup: every card, script and file in it.
- Keep Grok Bot's local-computer setting on "Ask every time".

### How the files ship
- The scripts and docs are plain files in the repo (https://github.com/AdventureNLearn/build-bridge). The cards carry instructions only, no script text.
- After its own YES, the bot downloads GitHub's archive of the repo (https://github.com/AdventureNLearn/build-bridge/archive/refs/heads/main.zip) into `<USER_HOME>\Downloads`, unzips it, and moves its `build-bridge-main` folder to `<PROJECT_DIR>\.build-bridge`.
- It checks every file against FINGERPRINTS.txt. If any file is missing, extra or different, the check prints that file and stops with exit 1, and nothing after it runs.
- The fingerprint check passed on Windows PowerShell 5.1 in that one PC run (it printed `FINGERPRINTS-OK 42 files`).
- Only the install files ship.

Placeholders: `<USER_HOME>` is your Windows profile folder. `<PROJECT_DIR>` is your one Build project folder. `https://github.com/AdventureNLearn/build-bridge` is the repo's address. `<BB_ROOT>` is `<USER_HOME>\.buildbridge` (or `BB_HOME`). `<BB_KEYS>` is `<BB_ROOT>-keys`. `<BB_SCANS>` is `<BB_ROOT>-scans`.

## What you do

Step and YES names are from the cards.

| Build Bridge will | You will need to |
|---|---|
| **Step 0, welcome.** Ask you to connect your own accounts first, then explain every step. Writes nothing. | Connect your own Grok Bot, webhook routine and Grok Build sign-in, never someone else's. Then reply **YES** to start with the read-only scan. |
| **Download and check.** Only after your own accounts are connected (step 0), download the repo archive (main.zip), unzip it, move `build-bridge-main` to `<PROJECT_DIR>\.build-bridge`, and check every file against its FINGERPRINTS.txt; on any missing, extra or different file it stops with exit 1 and nothing runs. | Reply **YES** to the download and check. Go on only if it ends with `exit code: 0`. |
| **Step 1, scan.** Reads your PC and changes nothing, except one baseline file `<BB_SCANS>\scan-1.txt` when saved with `-Save 1`. The scan lists startup entries and whether you are admin. | Reply **YES to scan**. |
| **Step 2, jobs folder.** Makes hidden `<BB_ROOT>` with outbox, inbox, done, rejected, bin, state, logs, keys-public. | Reply **YES**. |
| **Copy scripts** into `<BB_ROOT>\bin`. | Let it copy, as each card says. |
| **Step 3, signing key.** Your own RSA-3072 key pair. The private key `<BB_KEYS>\signing-private.dpapi` is sealed with Windows DPAPI for you. The public key is `<BB_ROOT>\keys-public\signing-public.xml`. | Reply **YES**. |
| **icacls on your own key folder.** No step asks for admin rights, and no script requests elevation. bb-keygen.ps1 runs `icacls <root>-keys /inheritance:r /grant:r *<own SID>:(OI)(CI)F`, then `/remove:g *S-1-5-18 *S-1-5-32-544` and any other non-owner entry, on it while it is still empty (a non-empty folder stops with nothing written), so only you have access. bb-common.ps1 runs `icacls <file> /inheritance:r /grant:r *<own SID>:F` on each key file it creates there. Both act only on the keys folder and key files under your own home. That this works as a normal user on every Windows PC is (not tested). | Expect no admin or UAC prompt. |
| **Step 4, watchers.** Outbox watcher `bb-watch-outbox.ps1` and reply watcher `bb-watch-inbox.ps1` run hidden. Bad jobs go to `rejected`. State goes in `<BB_ROOT>\state`, logs in `<BB_ROOT>\logs`. The listener `bb-listen.ps1` runs inside Build. Step 4 also replaces `<PROJECT_DIR>` in the copied `bb-pickup.ps1` with your project folder. | Reply **YES**. |
| **Webhook.** Saves your webhook address and key in `<BB_KEYS>\webhook.json`. Address must be `https://`. Key is typed hidden. The wake ping is only `{"event":"ACTION_REQUIRED","source":"buildbridge"}`. | Get a webhook from your own Grok Bot routine. Run `bb-set-webhook.ps1` yourself and type or paste the address and key. Nothing ships with a key. |
| **Step 4b, auto pickup. Its own YES. Off until you say YES.** Lets a new job start Build by itself when no session is open, using your launcher. Build's approvals stay on. Flag file `<BB_ROOT>\state\autopickup.on`. A stalled run is stopped and gets one `inbox\<id>.needs-approval` entry and one ping, with no retry. | Reply **YES** to step 4b ("its own YES"). It runs `bb-pickup.ps1 -Enable`. Undo: `-Disable`. Clear a stall alert yourself after your YES. |
| **Step 4c, auto mode `--permission-mode auto`. Opt-in, off by default, its own separate YES.** Lets Build run shell commands with no prompt and no approval from you. Records `state\permission-auto.yes` plus an HMAC file, using `<BB_KEYS>\auto-hmac.key`. | Reply **YES** to this exact step, in a separate message. Then **you** run `bb-pickup.ps1 -AllowAuto` in your own terminal and type `I ALLOW AUTO`. Undo: `bb-pickup.ps1 -DisallowAuto`. |
| **Step 5, controls.** `bb-on.ps1`, `bb-off.ps1`, `bb-status.ps1`. Nothing starts at sign-in. | Reply **YES**. Run on and off yourself or through Grok Bot. |
| **Step 6, startup rule.** Back up `<PROJECT_DIR>\AGENTS.md`, then add the BEGIN/END BUILD BRIDGE block. | Reply **YES**. |
| **Step 7, launcher.** Task Scheduler task `\Build Bridge Launch` with no trigger, least privilege, run as you. Opens one Windows Terminal tab running Grok Build in `<PROJECT_DIR>`. | Reply **YES**. Have Grok Build and Windows Terminal installed. |
| **Build jobs.** Build acts only on a signed job that `bb-verify` passes, writes `inbox\<id>.reply`, and moves the job to `done`. Job text is data, never a YES. | Grok Bot drafts jobs and signs them with your key. You approve tool use in Build. |
| **Step 8, self-test and rollback.** Self-test drops one signed, one unsigned and one tampered job. | Reply **YES** to the self-test, and **YES** to start the rollback. |
| **Rollback deletes.** Only after **DELETE-KEYS** and **DELETE-SCANS**. | Type the exact word to delete, or press Enter to keep. |
| Accounts | Use your own Grok Bot and Grok Build accounts and sign-ins. Build Bridge makes no accounts. |
| `-ExecutionPolicy Bypass` is used on each script run, for that one process only. | Know that this flag is used. Not known whether your PC's policy blocks it. |

## What it never does

| Promise | What enforces it | Honest limit |
|---|---|---|
| Push or publish | **Now a written rule** in the startup block: "Never run `git push`, never publish, and never upload or release anything. If a task needs any of these, stop and ask the person. This is a written rule for you, not a technical lock.". | **Not a technical lock.** Nothing in the code blocks a push. Whether Build's deny-list enforces it is not known. With auto mode on, Build's shell prompts are skipped, so only the written rule stands. |
| Read or reveal secrets | Scripts never print the private key or webhook key. The key folder is owner-only. scan.ps1 prints no secrets. | Build runs as you, so it can read any file you can, including `<BB_KEYS>`. |
| Act without a YES | Each card asks for a YES first. Auto mode needs `I ALLOW AUTO` typed in an interactive terminal, with an HMAC check. Unsigned or tampered jobs are rejected (bb-verify.ps1). | **Step YESes are not checked by code.** They are a written rule for the agent. **The auto YES can be forged** by anything running as you: the card itself calls it "a guard against mistakes, not a security boundary". |
| Skip human review | Build's approvals stay on by default. | **Auto mode skips human review** of shell steps. With 4b and 4c both on, jobs can run shell commands with nobody approving them. |
| Run things you can't see | bb-status shows what is on. | **Watchers and pickup run hidden** (no window). |
| Change PowerShell policy | `-ExecutionPolicy Bypass` is per process only. | **`-ExecutionPolicy Bypass` is used** on every script run. |

## Risks

- Build output and replies can include local paths, such as your user folder and project folder. Your bot reads them, so check output before sharing it.

## Limits

- The launcher does not start the outbox and reply watchers; run `bb-on.ps1` after launch.
- ExecutionPolicy Bypass: `bb-launch.ps1` and the watchers and scan cards still run PowerShell with `-ExecutionPolicy Bypass` for that one process. This is a known issue, kept as-is in v1.0.1, to be fixed in a later version.

### Known unknowns
- Windows PowerShell 5.1: One live run on one Windows 11 PC (PowerShell 5.1, Grok Build 1.0.70) passed the steps in TEST-LOG.md. The v1.0.1 keygen fix (bb-keygen.ps1 9072ed42) then passed a separate test-mode run on Windows PowerShell 5.1 (see TEST-LOG.md); the v1.0.1 webhook.json and auto-hmac.key write paths passed in test mode only (PC, PS 5.1); a one-hour live soak passed on one PC with auto-pickup off (see TEST-LOG.md). The step 7 installer (`install-launch-task.ps1`) passed on one Windows 11 PC (PowerShell 5.1): TASK-INSTALL-OK, launch task result 0, and the already-running guard held (see TEST-LOG.md). Longer soaks, auto-pickup and the rest stay [UNTESTED]: macOS/Linux, autopickup and 4c auto mode, mid-session idle pickup, sign-out/sign-in, soaks longer than one hour, multiple PCs.
- Windows 5.1 behavior of `Remove-Item` on ACL-locked key files: not known.
- Live icacls as a normal user: tested in an earlier revision in test mode on the test keys folder; not tested on this version. Not tested: the auto-mode key file (auto-hmac.key).
- Build deny-list enforcement of the never-push rule: not known.
- Whether standalone script files reach the installer: not known.
- The AGENTS.md halt and empty-file rules were tested on portable PowerShell 7.4.6 only, not on a live Windows PC.
- Rollback runs its child scripts with Windows PowerShell 5.1 from System32. This was tested in an earlier revision in test mode; not tested on this version.
- Other Bots can read your keys: every Bot on your account with local access could read `<BB_KEYS>`. The disclosure card covers it. (xAI docs, approvals page: "Do not use separate Bots as a security boundary.")
- What to do if your keys leak is not covered: not known.
- Scripts do not give child processes a minimal environment; child processes inherit the user's environment.

### xAI policy mapping

Quotes are short and verbatim from xAI policy pages, gathered 2026-10-25. No verdicts. "(search copy)" means the text was seen only in a search-engine copy.

- "Introducing viruses or malware ... or bypassing our systems or protective measures" (AUP, x.ai/legal/acceptable-use-policy, eff. Aug 14, 2026). Covered: What it never does (hidden runs, Bypass flag). Gap: Watchers run hidden; `-ExecutionPolicy Bypass` is used. Disclosed, not removed.
- "Disrupting, interfering with, or unauthorized access to the Service or its safety systems, including circumventing ... protective measures and safety mitigations" (AUP, Aug 14, 2026). Covered: Step 4c; What it never does (human review). Gap: Auto mode turns off Build's shell prompts after its own YES.
- "Accessing the Services through unauthorized automated or non-human means, whether through a bot, script, or otherwise" (AUP, Aug 14, 2026). Covered: Steps 4, 4b, 7. Gap: Scripts start Grok Build with nobody at the PC. Whether this counts as authorized is not known.
- "Modifying, copying, ... distributing, ... reverse engineer, decompile ... the source code of our Service" (AUP, Aug 14, 2026). Covered: How the files ship. Gap: none noted; Build Bridge ships its own scripts, not xAI code.
- "Taking unauthorized actions on behalf of others" (AUP, Aug 14, 2026). Covered: Build jobs (signed); What it never does (act without a YES). Gap: Step YESes not code-checked; auto YES can be forged by anything running as you.
- "Misleading others or not being transparent regarding your use of AI" (AUP, Aug 14, 2026). Covered: Top line (run by an AI assistant). Gap: Replies and changed files carry no AI label. Not known whether one is needed.
- "falsifying, forging, fabricating, or materially misrepresenting documents, records, identities, credentials, signatures" (AUP, Aug 14, 2026). Covered: Step 3 (your own signing key); What it never does (auto YES forgeable). Gap: The auto-YES record can be forged by anything running as you.
- "Respect guardrails and don't mislead. Don't circumvent safeguards" (AUP, Aug 14, 2026). Covered: What it never does; Step 4c; Who is responsible. Gap: Auto mode lowers one safeguard, by the person's own choice.
- "Engaging in espionage, hacking, defrauding, defaming, scamming, or spamming" (AUP, Aug 14, 2026). Covered: Webhook (content-free ping to your own address). Gap: none noted.
- "You are responsible for User Content and Agentic Actions" (Consumer Terms, x.ai/legal/terms-of-service, upd. Oct 12, 2026, s.4). Covered: Who is responsible. Gap: none.
- "you may be required to apply ... a disclosure stating that the content was generated or altered by artificial intelligence" (Consumer Terms, Oct 12, 2026, s.4). Covered: Top line. Gap: Files Build changes get no AI label.
- "You may not share your account credentials ... and are responsible for all activities that occur under your account" (Consumer Terms, Oct 12, 2026, s.2). Covered: You will need to (your own accounts, your own webhook key). Gap: none noted.
- "solely responsible for any impact ... including ensuring appropriate safeguards, testing, and monitoring are in place" (Consumer Terms, Oct 12, 2026, s.5). Covered: Tested on; Who is responsible; bb-status. Gap: See Tested on, below.
- "You must comply with ... our Acceptable Use Policy and any other documentation, guidelines, or policies" (Consumer Terms, Oct 12, 2026, s.3). Covered: This whole table. Gap: Docs pages not read are not known (rows below).
- "When using Output or SpaceXSI's name, logos ... attribute ... as detailed in our Brand Guidelines" (Consumer Terms, Oct 12, 2026, s.4). Covered: not checked. Gap: Brand Guidelines not read.
- "You will notify us immediately of any breach of security or unauthorized use of your User Account" (Consumer Terms, Oct 12, 2026, s.7). Covered: not covered. Gap: The disclosure does not say what to do if keys leak.
- "keeps its user credentials strictly confidential" (Enterprise Terms, x.ai/legal/terms-of-service-enterprise, upd. Aug 14, 2026, s.1.2). Covered: Step 3; webhook row. Gap: Only for business or API use.
- "misrepresent that any Output was human-generated" (Enterprise Terms, Aug 14, 2026, s.3.2). Covered: Top line. Gap: Only for business or API use.
- "Customer will comply with SpaceXSI's Acceptable Use Policy" (Enterprise Terms, Aug 14, 2026, s.2). Covered: AUP rows. Gap: Only for business or API use.
- "You are solely responsible for the creation, publication, and sharing of your AI bot, any agentic actions it performs" (Bot sharing terms, x.ai/legal/bot-sharing-terms, eff. Aug 22, 2026, search copy). Covered: Who is responsible. Gap: none.
- "Complying with all applicable laws ... including those about cybersecurity, commercial use, and deceptive practices" (Bot sharing terms, Aug 22, 2026, search copy). Covered: What it never does. Gap: Which laws apply is not known.
- "Reviewing your bot's configuration for sensitive information (API keys, internal URLs, customer data, personal information) before sharing" (Bot sharing terms, Aug 22, 2026, search copy). Covered: How the files ship (placeholders only; no key ships). Gap: none noted; scan before each share.
- "Anyone with the share link can view and install your bot's full configuration" (Bot sharing terms, Aug 22, 2026, search copy). Covered: Who is responsible. Gap: none.
- "Applying all appropriate disclosures" (Bot sharing terms, Aug 22, 2026, search copy). Covered: This document. Gap: What counts as appropriate is not known.
- "This bot may perform actions on your behalf ... executing tasks, and interacting with third-party services" / "SpaceXSI does not verify, endorse, or guarantee the functionality or safety of third-party bots" (Bot sharing terms, Aug 22, 2026, search copy). Covered: What you do table; Who is responsible. Gap: The disclosure does not repeat that xAI does not verify third-party bots.
- "You may not redistribute, re-share, or re-export this bot or its configuration without the creator's permission" (Bot sharing terms, Aug 22, 2026, search copy). Covered: not covered. Gap: none in Build Bridge's scope.
- "Grok Bot may perform autonomous actions on Customer's behalf ... executing code, modifying files" (Grok Bot Terms, x.ai/legal/grok-bot-terms, date not stated, search copy). Covered: What you do table. Gap: none noted.
- "Customer is solely responsible for ... configuring appropriate permissions, approval requirements ... and monitoring recurring or unattended activities" (Grok Bot Terms, date not stated, search copy). Covered: Who is responsible; steps 4b, 4c; bb-status. Gap: Watchers and pickup run hidden, unattended once on.
- "Approval and automated-review controls are provided as aids only" (Grok Bot Terms, date not stated, search copy). Covered: Who is responsible ("only aids"). Gap: none.
- "Customer will use appropriate human review before permitting Agentic Actions" (Grok Bot Terms, date not stated, search copy). Covered: Step YESes; What it never does (human review). Gap: With 4b and 4c on, shell steps run with no human review.
- "By connecting an account ... Customer instructs and authorizes Grok Bot to access, transmit, and interact with Customer Data" (Grok Bot Terms, date not stated, search copy). Covered: Webhook row. Gap: none noted.
- "The default is Ask every time." (Docs, docs.x.ai/grok-bot/approvals-security-and-privacy, date not stated). Covered: Who is responsible ("Ask every time"). Gap: none.
- "Always allow and Never set Execution on Local Computer for every Bot" (Docs, approvals page, date not stated). Covered: Who is responsible. Gap: none noted.
- "Do not send a password or one-time code in ordinary chat." (Docs, approvals page, date not stated). Covered: Webhook row (typed in your own terminal). Gap: none.
- "do not put secrets, customer data, or internal URLs in a Bot you share." (Docs, approvals page, date not stated). Covered: How the files ship. Gap: none noted.
- "Files, browser sessions, and command line credentials on that computer are available across your Bot roster." / "Do not use separate Bots as a security boundary." (Docs, approvals page, date not stated). Covered: What it never does (read secrets). Gap: Every Bot on your account with local access could read `<BB_KEYS>`. Not said in the cards.
- "Auto Review is model-based and should complement, not replace, least privilege and explicit approval boundaries." (Docs, approvals page, date not stated). Covered: Step YESes; Who is responsible. Gap: none noted.
- "Keep sending, publishing, purchasing, deletion, and production changes behind approval." (Docs, approvals page, date not stated). Covered: What it never does (push or publish); DELETE-KEYS, DELETE-SCANS. Gap: Publishing is a written rule only; auto mode skips shell approvals.
- "A Bot only runs commands on your local computer when that capability is enabled and you approve it" (Docs, docs.x.ai/grok-bot/computer-and-apps, date not stated). Covered: You will need to. Gap: Once on, watchers run with no per-command approval.
- "Do not place a credential or file on it if another Bot on your account should not be able to use it." (Docs, computer-and-apps, date not stated). Covered: Step 3. Gap: Same as the row above that says other Bots can read keys.
- "Ask the Bot to pause and notify you rather than attempting to bypass the check." (Docs, computer-and-apps, date not stated). Covered: Stall alert (step 4b); never-push rule ("stop and ask"). Gap: none noted.
- "Remove API keys, internal URLs, customer data ... before you share." (Docs, docs.x.ai/grok-bot/bots, date not stated, search copy). Covered: How the files ship. Gap: none noted.
- "admins control whether members can publish Bot templates publicly." (Docs, bots page, date not stated, search copy). Covered: not checked. Gap: Applies to Teams and Enterprise plans only.
- Template or marketplace review or listing rules: not checked.
- Rules specific to scripts, startup entries, watchers, webhooks and signing keys: not checked.
- Grok Build permissions policy (docs.x.ai/build/permissions returned 404): not checked.
- xAI Privacy Policy (not read): not checked.
- xAI Brand Guidelines (not read): not checked.
- Official xAI/Grok X posts on template policy (none searched or found): not checked.

## Watchers detail

Moved from the watchers card (step 4). One live run on one Windows 11 PC (PowerShell 5.1, Grok Build 1.0.70) passed the steps in TEST-LOG.md. The v1.0.1 keygen fix (bb-keygen.ps1 9072ed42) then passed a separate test-mode run on Windows PowerShell 5.1 (see TEST-LOG.md); the v1.0.1 webhook.json and auto-hmac.key write paths passed in test mode only (PC, PS 5.1); a one-hour live soak passed on one PC with auto-pickup off (see TEST-LOG.md). The step 7 installer (`install-launch-task.ps1`) passed on one Windows 11 PC (PowerShell 5.1): TASK-INSTALL-OK, launch task result 0, and the already-running guard held (see TEST-LOG.md). Longer soaks, auto-pickup and the rest stay [UNTESTED]: macOS/Linux, autopickup and 4c auto mode, mid-session idle pickup, sign-out/sign-in, soaks longer than one hour, multiple PCs.

### Stall alert
- Stall detection was tested in an earlier revision in test mode with a stand-in command, not Build (one-shot mode only; the tab-mode stall stop is not tested).
- Alert entry: `inbox/<id>.needs-approval`, one per job id, never duplicated, same layout as a reply and not signed (replies are not signed either). Fields: `v: 3`, `id`, `from: Build Bridge pickup`, `status: needs-approval`, `pickup` (ISO start time), `returned` (ISO stop time), then a body saying the run was stopped after no progress for 300 s, Build was most likely waiting for an approval nobody could give, nothing was retried, the permission mode was not changed, the job is still in outbox, and to finish it open Build and approve or give the separate auto YES (step 4c), then run `bb-pickup clear-approval <id>`; then `stop`.
- One wake ping, the usual wake-only body `{"event":"ACTION_REQUIRED","source":"buildbridge"}`. The reply watcher pings only for `*.reply`, so this entry gets no second ping.
- `bb-status` shows `waiting-for-approval: <id> (since <time>)` or `waiting-for-approval: none`.
- While the entry is open, pickup skips that job (`SKIP waiting-for-approval`) and the pickup prompt tells Build to skip it.
- What a stall stop stops: one-shot mode, the process pickup started plus its children. Tab mode, ONLY the tab host that appeared after this launch (recorded at first sight by pid, start time and command line, re-checked before the stop) plus its children, including its Build. Any other `grok --cwd <PROJECT_DIR>`, such as one opened by hand, is never stopped; nothing of another user's is touched.
- Both pickup modes are covered: the one-shot run (`<BUILD_ONESHOT_CMD>`, not given here) and the launcher-tab fallback. In tab mode progress means a new file in `inbox/` or `done/`, and a stall closes only this user's tab host at the full installed path and Build for `<PROJECT_DIR>`, matched as bb-off does (not tested).
- Settings: `BB_PICKUP_STALL` and `BB_PICKUP_POLL` are whole seconds 1 to 86400; `BB_PICKUP_MAX_RUN` is 1 to 604800. Each must be digits only, at most 6 digits; 0, huge or non-numeric values are refused with exit 3. `BB_PICKUP_STALL` must be less than `BB_PICKUP_MAX_RUN`.

### Mid-session pickup (known issue, not tested)
- Finding in an earlier revision: in an open, idle Build session the listener prints the wake line but Build does nothing; a background child process cannot start a turn in an idle interactive session. Every pickup that worked came from the launcher's starting prompt.
- Tested in an earlier revision in test mode, without Build doing a job: pickup starts with no human step, and an open session is left alone with the job logged as queued. Not tested: an open session picking the job up on its next turn, and Build itself starting and finishing a job.
- Turn check: the startup rule and starting prompt tell Build to check `outbox/` at the start of every turn and after every finished task, so an open session picks up a job on its next turn, not on arrival.
- Pickup when no session is open (`bb-pickup`, opt-in): after a good job the outbox watcher calls `bb-pickup run`, which does nothing unless auto pickup is on. If a Build session for `<PROJECT_DIR>` is open it logs `QUEUED` and leaves the job for that session. Otherwise it takes a lock so only one pickup runs, and starts one run.
- One-shot run: `<BUILD_ONESHOT_CMD>` with `{PROMPT_FILE}`. The prompt is never in the command string: pickup writes `state/pickup-prompt.txt`, puts its quoted path in `{PROMPT_FILE}`, feeds it on stdin and sets `BB_PROMPT_FILE`. Which one Build reads is not known; take it from Build's docs. The old `{PROMPT}` token is refused (so is an older template like `-p "$PROMPT"`). Fill the command only from Build's docs, never with an always-approve or bypass flag.
- Command allow-list: letters, digits, space and `. _ / \ : = , + @ { } " ' -` only. Anything else (`% $ ! ^ ; & | ( ) \` < > * ? ~ # [ ]`, non-ASCII) is refused, so `%PM%`, `$PM`, `${PM}` or `!PM!` can never carry a flag. This replaces the older rule that refused only `%`, `$` or `!` near `--permission-mode`. A Windows 8.3 short path with `~` in the Build Bridge folder would be refused too (not tested).
- Fallback while the placeholder is unfilled: the step-7 launcher opens one new tab with the starting prompt; it stays open until `off` or the person closes it.
- The wake ping stays wake-only: it says "check the inbox" when a reply lands and carries no job.
- Pickup lock: Windows named mutex `Local\BuildBridge-pickup`, freed by Windows when the process ends, so no age check or takeover. `BB_PICKUP_MAX_RUN` (default 3600 s) is the longest one run may last; set it longer than your longest Build run.
- Refused one-shot flags: `--permission-mode auto` unless a valid step-4c YES is recorded (matched after normalizing: quotes and `^` removed, Unicode dashes turned into `-`, spaces around `=` closed up, and `; & | && || ( ) ` + "`" + ` < >` read as spaces, so `"auto"`, `'auto'`, `=auto`, `auto;`, `auto&&next` all count; characters outside the allow-list are refused first); yolo, dangerous, --force, always-approve, auto-approve, skip-permission / skip_permission, bypass, no-confirm, no-verify, trust-all, and `-y` / `--yes` as separate words. A refused command prints `REFUSED` and exits 3.
- Headless pickup round trip (earlier revision, live Windows): it completed only with permission mode `auto`. With `acceptEdits` (plain file edits approved with no prompt, shell steps still ask) it stalled on one shell step nobody could approve. No bypass or always-approve flags were used. `auto` runs shell steps WITHOUT a prompt, so Build's shell approvals are NOT on under `auto`; that is why it is off by default with its own YES (step 4c). Every other bypass or always-approve flag stays refused. The exact `<BUILD_ONESHOT_CMD>` syntax for the mode is not known; take it from Build's docs.

## Tested on

One live run on one Windows 11 PC (PowerShell 5.1, Grok Build 1.0.70) passed the steps in TEST-LOG.md. The v1.0.1 keygen fix (bb-keygen.ps1 9072ed42) then passed a separate test-mode run on Windows PowerShell 5.1 (see TEST-LOG.md); the v1.0.1 webhook.json and auto-hmac.key write paths passed in test mode only (PC, PS 5.1); a one-hour live soak passed on one PC with auto-pickup off (see TEST-LOG.md). The step 7 installer (`install-launch-task.ps1`) passed on one Windows 11 PC (PowerShell 5.1): TASK-INSTALL-OK, launch task result 0, and the already-running guard held (see TEST-LOG.md). Longer soaks, auto-pickup and the rest stay [UNTESTED]: macOS/Linux, autopickup and 4c auto mode, mid-session idle pickup, sign-out/sign-in, soaks longer than one hour, multiple PCs.

## How to remove it

1. Turn it off: `bb-off.ps1 -ProjectDir "<PROJECT_DIR>"`. Check `bb-status.ps1` shows every line `off`.
2. Reply YES to the rollback, then run `bb-rollback.ps1 -ProjectDir "<PROJECT_DIR>" -Rescan <path to scan.ps1>`. Run the scan from the package or a temp copy, not from `<BB_ROOT>\bin`.
3. **AGENTS.md check first.** Before bb-off, the task delete or any move, the rollback runs `remove-startup-rule.ps1 -CheckOnly`. It stops if the markers are missing, duplicated, changed or out of order, or if AGENTS.md is missing or would not keep its exact bytes. Then it prints `ROLLBACK-HALTED`, says what to fix, says to run the removal again, exits 7, and changes nothing. The check is skipped only when the project folder has no `AGENTS.md.buildbridge-backup-*` or `-none-*` file, or `remove-startup-rule.ps1` is not in bin. By design, the whole removal stops until AGENTS.md is fixed.
   **Windows PowerShell 5.1:** on a real PC, rollback runs its child scripts, including the AGENTS.md check and step 6, with Windows PowerShell 5.1 from System32. One live run on one Windows 11 PC (PowerShell 5.1, Grok Build 1.0.70) passed the steps in TEST-LOG.md. The v1.0.1 keygen fix (bb-keygen.ps1 9072ed42) then passed a separate test-mode run on Windows PowerShell 5.1 (see TEST-LOG.md); the v1.0.1 webhook.json and auto-hmac.key write paths passed in test mode only (PC, PS 5.1); a one-hour live soak passed on one PC with auto-pickup off (see TEST-LOG.md). The step 7 installer (`install-launch-task.ps1`) passed on one Windows 11 PC (PowerShell 5.1): TASK-INSTALL-OK, launch task result 0, and the already-running guard held (see TEST-LOG.md). Longer soaks, auto-pickup and the rest stay [UNTESTED]: macOS/Linux, autopickup and 4c auto mode, mid-session idle pickup, sign-out/sign-in, soaks longer than one hour, multiple PCs.
   Then it undoes steps in reverse: runs off, **deletes** the `\Build Bridge Launch` scheduled task with `schtasks /Delete`, then the step 6 undo:
   - It saves the current AGENTS.md as `AGENTS.md.before-bb-remove-<stamp>`. This copy is kept, not deleted.
   - It removes only the lines from the BEGIN marker through the END marker. Every other byte is kept.
   - If Build Bridge created AGENTS.md and only spaces, CR and LF are left, the file is deleted. The copy stays. Only spaces, CR and LF count as empty. A tab or any other character means the file is kept.
   - Then it deletes the install-time backup or marker. The pre-install backup is never copied over AGENTS.md.
   - **Honest limit:** the check runs only at the start. If AGENTS.md is edited during the rollback, after the check, step 6 can still STOP. Then the rollback halts with `ROLLBACK-HALTED` and exit 7. By then bb-off has run and the scheduled task is already deleted. Bin, keys and the folder are not moved, and nothing else is deleted. Fix AGENTS.md and run the removal again.
   Then it **moves aside** (does not delete) `<BB_KEYS>` and `<BB_ROOT>` to `-removed-<stamp>` folders. Then the rescan prints SCAN-MATCH or SCAN-DIFF.
4. **DELETE-KEYS.** The script says where the keys folder was moved and suggests deleting it. Type `DELETE-KEYS` exactly to delete that one folder `<BB_KEYS>-removed-<stamp>` (private key, webhook.json, auto-hmac.key).
5. **DELETE-SCANS.** Then, separately, it says `<BB_SCANS>` holds a snapshot of your PC, such as the startup list, and suggests deleting it. Type `DELETE-SCANS` exactly to delete it.. Keys are deleted only after their own typed `DELETE-KEYS`.
6. **Any other answer, or no way to answer** (no console, input redirected), deletes nothing and prints where the folder still is: `KEYS KEPT at: <path>`, `SCANS KEPT at: <path>`.
**Everything the rollback deletes with no typed word** (checked in the code):
- The scheduled task `\Build Bridge Launch`. Always removed, with `schtasks /Delete`.
- The install-time AGENTS.md backup `AGENTS.md.buildbridge-backup-<stamp>`, or the marker `AGENTS.md.buildbridge-none-<stamp>`. The step 6 undo deletes the newest one, only after the section was removed.
- `<PROJECT_DIR>\AGENTS.md` itself, only when Build Bridge created it (the marker exists) and only spaces, CR and LF are left after the section is removed. A file with a tab or any other character is kept. Its copy `AGENTS.md.before-bb-remove-<stamp>` is saved first and kept.
- When AGENTS.md has other text, it is rewritten without the Build Bridge section. Every other byte is kept, including your edits.
- On any AGENTS.md STOP, none of these AGENTS.md changes happen.
- `<BB_SCANS>\scan-2.txt`, overwritten when `-Rescan` saves a new one.

**Deleted only on a typed word:** the moved-aside keys folder, on `DELETE-KEYS`, and the scans folder, on `DELETE-SCANS`. Also kept: the copy `AGENTS.md.before-bb-remove-<stamp>` in `<PROJECT_DIR>`.

**Moved aside, not deleted:** `<BB_KEYS>` and `<BB_ROOT>` (with `bin`, the watchers and controls inside). `bb-off` only stops processes.

The scans folder `<BB_SCANS>` holds no keys. It is a snapshot of your PC, such as the startup list.

7. Check: SCAN-MATCH; `schtasks /Query /TN "Build Bridge Launch"` finds nothing; AGENTS.md has no `BEGIN BUILD BRIDGE` (or is gone, if Build Bridge created it and it was empty); `AGENTS.md.before-bb-remove-<stamp>` exists if AGENTS.md had a section; no `ROLLBACK-HALTED` was printed; `DELETE-KEYS done` and `DELETE-SCANS done` were printed, or you know where the kept folders are.
8. Left on purpose: the moved-aside `<BB_ROOT>-removed-<stamp>` folder is not deleted by the rollback; deleting it needs its own YES. The downloaded files can be cleared by deleting `<PROJECT_DIR>\.build-bridge`, `<USER_HOME>\Downloads\bb-unzip` and `<USER_HOME>\Downloads\build-bridge-main.zip`. Remove your webhook in your Grok Bot routine.
