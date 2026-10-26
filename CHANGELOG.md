# Build Bridge changelog

## r35 (2026-10-26)
- Known gap: Scripts do not give child processes a minimal environment; child processes inherit the user's environment.

## First release (2026-10-25)
The first public version.
- Windows only. Install files only.
- Never push or publish: the AGENTS.md startup block tells Build never to run git push, publish, upload or release anything, and to stop and ask instead. This is a written rule, not a technical lock.
- Removal saves a copy of AGENTS.md, removes only the Build Bridge section, and stops without changing anything if the section markers are wrong. It asks for a typed `DELETE-KEYS` and, separately, `DELETE-SCANS` before deleting those folders.
- Support: provided as is, no support, use at your own risk.

## Limits
- Earlier revisions had a test-mode run on one Windows PC. This version is tested on the author's box only; no Windows PC staging run or soak has been done.
- Not tested yet: Build itself starting and finishing a job with no one at the PC, and whether Build enforces its deny list.

## How to check the pinned content
DISCLOSURE.md pins the "content tree": every file in this package except eight. Two of them hold the statement: package/DISCLOSURE.md and its summary, the disclosure card share/disclosure/SKILL.md. The other six are lists of hashes: package/MANIFEST.md, SHARE-MANIFEST.md, files.json, SHARE-CHECKSUMS.txt, cards.json and MANIFEST.share.md. The lists only restate the hashes of the other files, so leaving them out loses nothing, and the pin does not change when the statement changes. To recompute it, run this from the top folder of the package (bash):

```
find . -type f ! -path ./package/DISCLOSURE.md ! -path ./share/disclosure/SKILL.md ! -path ./package/MANIFEST.md ! -path ./SHARE-MANIFEST.md ! -path ./files.json ! -path ./SHARE-CHECKSUMS.txt ! -path ./cards.json ! -path ./MANIFEST.share.md -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-8
```

The result must equal the content tree value in DISCLOSURE.md.
