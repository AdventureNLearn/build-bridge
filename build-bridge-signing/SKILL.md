---
name: build-bridge-signing
description: 'Step 3 of Build Bridge: make the person''s own signing key pair, then sign every job and verify it before Build acts. Use for step 3 and whenever a job is filed or checked.'
---

# Build Bridge, step 3: signing key (on by default)

## Purpose
Make the person's own signing key pair, sign every job, and verify each job before Build acts on it.

## Steps

Ask: "Step 3 makes your own key pair. The private half stays in a locked folder only your account can open, `<USER_HOME>\.buildbridge-keys`, which holds the private key, webhook.json and auto-hmac.key, and never goes to chat or Grok Bot's servers. Build only gets the public half, which can check jobs but can't make them. Reply YES." Wait for YES.

Copy this folder's scripts into `<USER_HOME>/.buildbridge/bin/`, then:
- Windows: `bb-keygen.ps1`. RSA-3072, private key sealed with Windows DPAPI for this user and folder ACL set to the user only (`icacls /inheritance:r /grant:r`, then `/remove:g *S-1-5-18 *S-1-5-32-544` and any other non-owner entry, on the empty folder only; a folder with any entry stops (exit 3) with nothing written). Public key `keys-public/signing-public.xml`. Not tested: the key-pair form is new; the reference setup used a different signing form. Same DPAPI and folder pattern.
Never `cat`, print, upload or paste the private key. Don't read it to "check" it; the check below is enough.

## Check
Prints `KEYGEN-OK owner-only=True`; then sign `job.example` from the jobs-folder skill and run verify → `VERIFY-OK`; edit one word → `REJECT BAD_SIG`.

## Reference: signing a job (Grok Bot side, on the person's computer)
1. Write a draft (formats in build-bridge-jobs-folder) to a temp file, with no `sig:` line.
2. `bb-sign.ps1 -Draft <file>`: checks fields, signs the canonical text, writes `outbox/<id>.job` atomically. Prints `SIGNED <id>`.

Canonical text = the eight fields `v,id,from,to,priority,time,job,done-when`, in that order, each as `name=value`, value trimmed with inner whitespace collapsed to one space, joined by `\n`, UTF-8. Signature = RSA PKCS#1 v1.5 over SHA-256, base64 on one line. Unknown or repeated field names are refused (BAD_FIELD), so nothing unsigned can be slipped in.

## Reference: verifying (Build side and outbox watcher)
`bb-verify.ps1 -File <job>` → exit 0 `VERIFY-OK <id>`, or exit 2 `REJECT <UNSIGNED|BAD_SIG|BAD_FIELD|MISSING_FIELD|OLD_FORMAT|BAD_PRIORITY|BAD_ID|NAME_MISMATCH|ERROR>`. Rejected jobs are never run.

## Undo
Turning signing off: only after a second explicit YES with this warning: "Without signing, anything that can write to your jobs folder can give Build orders." Then watchers are started with `-AllowUnsigned` / `BB_ALLOW_UNSIGNED=1`. Undo: restart them without it.

Step 3 itself: `undo-keys.ps1` moves the key folder and public key to `*-removed-<stamp>` (no delete without a YES). undo-keys moves the keys aside; only the rollback's DELETE-KEYS prompt deletes them. After undo, every new job is rejected until step 3 runs again.
