# Build Bridge

## Risks / read first

- Security boundary: jobs are signed and checked before they run, all files stay local on the PC, and only the wake ping leaves the PC.
- Read [DISCLOSURE.md](DISCLOSURE.md) before installing.
- Build output and replies can include local paths, such as your user folder and project folder. Your bot reads them, so check output before sharing it.
- One live run on one Windows 11 PC (PowerShell 5.1, Grok Build 1.0.70) passed the steps in TEST-LOG.md. The v1.0.1 keygen fix (bb-keygen.ps1 9072ed42) then passed a separate test-mode run on Windows PowerShell 5.1 (see TEST-LOG.md); the v1.0.1 webhook.json and auto-hmac.key write paths passed in test mode only (PC, PS 5.1); a one-hour live soak passed on one PC with auto-pickup off (see TEST-LOG.md). The step 7 installer (`install-launch-task.ps1`) passed on one Windows 11 PC (PowerShell 5.1): TASK-INSTALL-OK, launch task result 0, and the already-running guard held (see TEST-LOG.md). Longer soaks, auto-pickup and the rest stay [UNTESTED]: macOS/Linux, autopickup and 4c auto mode, mid-session idle pickup, sign-out/sign-in, soaks longer than one hour, multiple PCs.

## What it does

Build Bridge lets your own Grok Bot hand jobs to Grok Build on your own Windows PC. Grok Bot writes a job, signs it with your own key and drops it in a hidden jobs folder. A watcher checks the signature and rejects anything unsigned or changed. Build does the signed job, writes a reply, and your own webhook wakes Grok Bot to read it. Jobs and replies are local files; the only thing that leaves your PC is the wake ping to your own webhook, and it carries no job text, paths or secrets.

Everything is plain PowerShell scripts, one Task Scheduler task and local files. The scripts and docs are plain files in this repo (https://github.com/AdventureNLearn/build-bridge). The bot downloads GitHub's archive of this repo (https://github.com/AdventureNLearn/build-bridge/archive/refs/heads/main.zip, the same as Code > Download ZIP), unzips it, moves its `build-bridge-main` folder to `<PROJECT_DIR>\.build-bridge`, checks every file against the repo's FINGERPRINTS.txt, and stops if any file is missing, extra or different.

The fingerprint check passed on Windows PowerShell 5.1 in that one PC run (it printed `FINGERPRINTS-OK 42 files`).

One live run on one Windows 11 PC (PowerShell 5.1, Grok Build 1.0.70) passed the steps in TEST-LOG.md. The v1.0.1 keygen fix (bb-keygen.ps1 9072ed42) then passed a separate test-mode run on Windows PowerShell 5.1 (see TEST-LOG.md); the v1.0.1 webhook.json and auto-hmac.key write paths passed in test mode only (PC, PS 5.1); a one-hour live soak passed on one PC with auto-pickup off (see TEST-LOG.md). The step 7 installer (`install-launch-task.ps1`) passed on one Windows 11 PC (PowerShell 5.1): TASK-INSTALL-OK, launch task result 0, and the already-running guard held (see TEST-LOG.md). Longer soaks, auto-pickup and the rest stay [UNTESTED]: macOS/Linux, autopickup and 4c auto mode, mid-session idle pickup, sign-out/sign-in, soaks longer than one hour, multiple PCs.

## What you need

- A Windows PC and your normal user account (no admin rights are used).
- Windows PowerShell 5.1 (built into Windows) and Windows Terminal.
- Grok Build installed and signed in with your own account, and one Build project folder (`<PROJECT_DIR>`).
- Your own Grok Bot, and a webhook from your own Grok Bot routine. Use only your own accounts; nothing ships with a webhook or key.

Placeholders: `<USER_HOME>` is your Windows profile folder, `https://github.com/AdventureNLearn/build-bridge` is this repo's address, `<BB_ROOT>` is `<USER_HOME>\.buildbridge`, `<BB_KEYS>` is `<BB_ROOT>-keys` and `<BB_SCANS>` is `<BB_ROOT>-scans`.

## Steps

Each step is explained first, waits for your YES, then runs and shows a check and an undo.

0. **Connect your own accounts** (your own Grok Bot, webhook routine and Build sign-in) and reply YES. Nothing is created or installed before this. Then, after its own YES, the bot downloads the repo archive, unzips it and runs the fingerprint check; on any mismatch it stops (exit 1) and nothing runs.
1. **Scan.** Reads your setup and changes nothing except one baseline file, `<BB_SCANS>\scan-1.txt`.
2. **Jobs folder.** Makes the hidden `<BB_ROOT>` folder.
3. **Signing key.** Makes your own key pair. The private key stays on your PC, locked to your account.
4. **Watchers.** Starts the outbox and reply watchers. **You** run `bb-set-webhook.ps1` in your own terminal and type your webhook address and key there, never in chat.
   - 4b. Optional auto pickup: lets a new job start Build when no session is open. Its own YES; Build's approvals stay on.
   - 4c. Optional auto mode: lets Build run shell steps with no prompt. Off by default, its own separate YES, and you type `I ALLOW AUTO` yourself.
5. **Controls.** `bb-on.ps1`, `bb-off.ps1` and `bb-status.ps1`. Nothing starts at sign-in.
6. **Startup rule.** Backs up `<PROJECT_DIR>\AGENTS.md` and adds the Build Bridge block.
7. **Launcher.** A Task Scheduler task with no trigger that opens one Build tab on demand.
8. **Self-test and rollback drill.** One signed, one unsigned and one tampered job; only the signed one should run.

The disclosure card (`disclosure`) is a short summary; [DISCLOSURE.md](DISCLOSURE.md) lists what Build Bridge does and what you do at each step.

## Daily use

- Turn it on and off with `bb-on.ps1` and `bb-off.ps1`; check it with `bb-status.ps1`.
- Ask Grok Bot for a job. You approve tool use in Build. Grok Bot reports back when the reply arrives.
- If Build is closed and a hands-off job stops for an approval, it waits for you. Pickup stops that run, writes one `inbox\<id>.needs-approval` entry and sends one wake ping. Clear it yourself with `bb-pickup.ps1 -ClearApproval <id>` after you've looked.
- Known issue: an open, idle Build session is not woken by a new job.

## Troubleshooting

- Run `bb-status.ps1` first; it shows what is on and off.
- Look in `<BB_ROOT>\logs` and `<BB_ROOT>\rejected` (each rejected job has a `.reason` file).
- If a script is blocked, check your PC's PowerShell execution policy.
- If the webhook ping fails, check the address and key in your own Grok Bot routine and run `bb-set-webhook.ps1` again.

## How to undo it

1. Run `bb-off.ps1` and check `bb-status.ps1` shows every line `off`.
2. Reply YES to the rollback, then run `bb-rollback.ps1`. It first checks the Build Bridge section in AGENTS.md; if anything is wrong it prints `ROLLBACK-HALTED`, changes nothing and tells you what to fix.
3. It undoes each step in reverse and moves your Build Bridge folders aside. Use `Get-ChildItem -Force <USER_HOME>` to see them, because the jobs folder stays hidden.
4. Type `DELETE-KEYS` to delete your keys and, separately, `DELETE-SCANS` to delete the scans folder. Any other answer keeps them and prints where they are.
5. Remove the webhook in your Grok Bot routine.

## Who is responsible

- You, the person installing Build Bridge, are responsible for what the agent does on your PC.
- The publisher of this shared bot, not xAI, is responsible for the shared bot.
- The YES prompts and approvals are only aids. They are not guarantees.
- Anyone with the share link can see the full setup: every card, script and file in it.
- Keep Grok Bot's local-computer setting on "Ask every time".

## Support

Provided as is, no support, use at your own risk.

## Version

Version 1.0
