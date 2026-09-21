---
description: Work one item from agent/backlog.json through to verified and committed
---

Work exactly one item from the work queue in `agent/backlog.json`. Read
`docs/agent-work-queue.md` if you have not seen the method.

1. Run `node agent/next-issue.mjs --brief` and read the item it prints. If it reports nothing
   open, stop and say so.
2. Load ONLY that item's context: the files it names, its acceptance check and its evidence. Do
   not read the rest of the backlog.
3. If it is a defect, reproduce it first - a failing check, or a fresh screenshot of the bad state.
4. Make the smallest change that satisfies the acceptance check.
5. Verify with the named check. A fix without a passing check is not done. Never weaken the check,
   skip a test, or edit the acceptance to make it pass. Run builds through the project lock
   (`./agent/gradle-lock.ps1 -Command '.\gradlew.bat <tasks>'`) so a concurrent build cannot corrupt
   shared outputs and hand you a failure that is not in the code.
6. Commit that item alone, naming its id in the message.
7. Record the result:
   `node agent/next-issue.mjs --set <id> --status fixed --commit <sha> --verified "<evidence>"`
   or, after three failed attempts,
   `node agent/next-issue.mjs --set <id> --status blocked --note "<smallest unblocking action>"`

Report: the id, the check you ran and its real result, the commit, and the remaining open count.
Do not report an unrun check as passing.

$ARGUMENTS
