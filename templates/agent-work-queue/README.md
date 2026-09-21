# agent-work-queue template

Drop-in files for the agent work-queue method described in `docs/agent-work-queue.md`. The point
is to keep a large list of small fixes on disk and hand the agent **one item at a time**, so no
single conversation has to hold the whole programme.

## Files

| File | Goes to | Purpose |
|---|---|---|
| `next-issue.mjs` | `<project>/agent/next-issue.mjs` | Prints the next open item, or records a result |
| `backlog.schema.json` | `<project>/agent/backlog.schema.json` | The item shape |
| `backlog.example.json` | `<project>/agent/backlog.json` | Starting queue (replace with your items) |
| `gradle-lock.ps1` | `<project>/agent/gradle-lock.ps1` | Runs a build under a per-project lock so concurrent builds cannot corrupt shared outputs |
| `commands/ux-issue.md` | `~/.config/opencode/commands/ux-issue.md` | A `/ux-issue` command that runs one iteration |

Adopt it with `scripts/install-agent-work-queue.ps1 -ProjectPath <dir>` (add `-DryRun` to preview),
or copy the files yourself.

## The loop, in one screen

```
node agent/next-issue.mjs --brief     # 1. read one item (nothing else)
   ... fix it, verify with the named check, commit it alone ...
node agent/next-issue.mjs --set UX-001 --status fixed --commit <sha> --verified "<evidence>"
node agent/next-issue.mjs --brief     # 2. next item, fresh context
node agent/next-issue.mjs --status    # {"open":27,"fixed":6,...}
```

## Rules that make it finish

1. **One item in progress.** Do not start a second until the first is committed and recorded.
2. **State on disk.** The conversation may end at any time; `backlog.json` is the truth.
3. **A check per item.** Build, test or fresh capture. No check, no "done".
4. **Fresh context per item.** Load only the current item's files and evidence.
5. **Commit per item**, message names the id.
6. **Three strikes = blocked**, with the smallest unblocking action recorded - never a weakened
   check.
7. **One build at a time per project.** Run builds as
   `./agent/gradle-lock.ps1 -Command '.\gradlew.bat <tasks>'`; two builds of one checkout corrupt
   each other's shared outputs.

## Item ids

`AREA-NNN` (e.g. `UX-014`, `PERF-003`). Keep them stable once created; they are what the loop and
the commit messages refer to.
