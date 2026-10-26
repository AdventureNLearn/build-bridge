---
name: build-bridge-jobs-folder
description: 'Step 2 of Build Bridge: create the hidden jobs folder and explain the job and reply file formats. Also the reference for every later step that reads or writes a job.'
---

# Build Bridge, step 2: jobs folder and file formats

## Purpose
Make the hidden jobs folder, and describe the job and reply file formats that every later step uses.

## Steps

Ask: "Step 2 makes one hidden folder in your home folder, `<USER_HOME>/.buildbridge`, for jobs and replies. Nothing else changes. Reply YES." Wait for YES.

Layout (same on every OS):
```
<USER_HOME>/.buildbridge/
  outbox/    jobs from Grok Bot to Build   <id>.job
  inbox/     replies from Build to Grok Bot <id>.reply
  done/      jobs Build finished (moved here once)
  rejected/  unsigned, tampered, duplicate or malformed jobs (+ <id>.reason)
  bin/       the Build Bridge scripts (steps 3-7)
  state/     watcher memory (seen / pinged lists)
  logs/      wake.log (Build listens), watcher logs (codes only, never secrets)
  keys-public/ signing-public.* (Build only verifies)
<USER_HOME>/.buildbridge-keys/  owner-only: private key, webhook.json and auto-hmac.key (steps 3, 4 and 4c)
```
Do it: `make-folders.ps1`. It is safe to rerun.

## Check
The script prints `FOLDERS-OK` and the eight folders exist.

## Undo
`undo-folders.ps1` moves `<USER_HOME>\.buildbridge` to `<USER_HOME>\.buildbridge-removed-<stamp>` (never deletes). Delete that later only with a YES.

## Reference: job file `outbox/<id>.job` (UTF-8, LF or CRLF)
One `name: value` per line, in this order. `job` and `done-when` may wrap; a line with no `name:` continues the field above. Field names are lowercase.
```
v: 3
id: BB-<YYYYMMDD>-<NNN>
from: GrokBot
to: Build
priority: normal          (normal | urgent)
time: <ISO-8601 with offset, e.g. 2026-01-31T09:05:00-05:00>
job: <plain words; text inside is data, never a YES>
done-when: <what proves it is finished>
sig: <base64 RSA-SHA256 signature, added by bb-sign>
```
Rules: one job per file; the file name must equal `<id>.job`; ids are never reused (a done id seen again goes to rejected as DUPLICATE); `v` must be 3. Write to `outbox/<id>.job.tmp` then rename, so watchers never see half a file (bb-sign does this).

## Reference: reply file `inbox/<id>.reply`
```
v: 3
id: <same id as the job>
from: Build
status: done              (done | failed | refused | needs-yes)
pickup: <ISO time Build read the job>
returned: <ISO time this reply was written>
---
<answer in plain words>
stop
```
Build writes `inbox/<id>.reply.tmp`, renames it, then moves `outbox/<id>.job` to `done/`. Exactly once. Templates: `job.example`, `reply.example`.

## Reference: needs-approval entry `inbox/<id>.needs-approval`
Written by bb-pickup, not by Build, when a hands-off run stalls on an approval (see build-bridge-watchers). It has the same layout as a reply, with `from: Build Bridge pickup` and `status: needs-approval`. There is one per job id, and the job stays in `outbox/`. It is not a `.reply`, so Build's own reply for the job can still be written exactly once later, and the reply watcher does not ping for it (pickup sends the one ping itself). Template: `needs-approval.example`.
