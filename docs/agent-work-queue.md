# The agent work queue

How to run a large body of small changes through an AI coding agent **across sessions** without
losing work, without re-doing work, and without any single conversation needing to hold the whole
programme in its head.

This is the method this repository recommends. It exists because the obvious approach - "ask the
agent to fix all 30 things" - fails for a reason that has nothing to do with the agent's skill.

---

## The problem

An agent works inside a **context window**: a finite working memory holding the conversation so
far. Reading screenshots, large source files and test logs fills it. When it fills, the agent can
no longer do large steps safely, and an interrupted edit can leave the tree half-changed.

The failure is therefore structural: **the programme lives in the agent's memory instead of on
disk.** Any workflow that depends on one conversation remembering everything is fragile by design.

## The fix

Five rules, each borrowed from an existing practice:

| Rule | Where it comes from |
|---|---|
| **1. One item in progress at a time (WIP = 1)** | Kanban / theory of constraints single-piece flow |
| **2. State lives on disk, never only in the conversation** | Event sourcing / a durable ledger; the agent's memory is a cache, not the source of truth |
| **3. Every item has an explicit acceptance check** | Scrum "Definition of Done"; test-driven development |
| **4. One item per fresh context** | Retrieval + sub-agent delegation: load only the current item, then discard |
| **5. Commit per item; the ledger records the commit** | Atomic commits; git as the checkpoint log |
| **6. One build at a time per project** | Mutual exclusion; shared build outputs are a critical section |

The queue is the whole trick: the agent never needs to remember item 27 while doing item 3. It
reads item 3 from disk, does it, writes the result back, and forgets it.

## The artifacts

In the **project**:

```
agent/backlog.json          the queue: one object per work item (the durable state)
agent/backlog.schema.json   the shape, so the file can be validated
```

In the **agent session**, no artifact: each item is handled by a task brief generated from the
queue (see `next-issue.mjs`).

## The loop

For each iteration:

1. **Pick** the next `open` item, highest severity first, with `next-issue.mjs`.
2. **Load only that item's context**: its problem statement, its acceptance check, and the files
   it names. Do not re-read the whole programme.
3. **Reproduce** the problem if it is a defect (a failing check before the fix).
4. **Fix** the smallest change that satisfies the acceptance check.
5. **Verify** with the named check - build, tests, or a fresh capture. A fix without a check is
   not done.
6. **Commit** the item alone, with a message naming its id.
7. **Update** the item: `status`, `commit`, `verified`, and any `note`.
8. **Repeat** from a fresh context.

If an item fails its check three times, set `status: "blocked"`, record the **smallest unblocking
action**, and move to the next item. Do not weaken the check to move on.

## Serialize builds

WIP = 1 applies to the *build*, not just the item. Two Gradle invocations against one checkout share
`app/build/...`; if their tasks interleave, or one is killed mid-write, they leave truncated shared
artifacts (a corrupt `test-results` binary, a half-written jar). The agent then sees a failure that
is not in the code and can burn a whole repair cycle on it.

Parallel workers are the common way to break this, but even a single orchestrator and a background
task can overlap. Hold the lock whenever a build may overlap another:

```powershell
# agent/gradle-lock.ps1 is installed alongside next-issue.mjs
./agent/gradle-lock.ps1 -Command '.\gradlew.bat :app:testDebugUnitTest --rerun-tasks'
```

It takes a machine-wide named mutex keyed by the project directory, so different projects still
build in parallel and only builds of the same checkout serialise. See
`docs/environment-gaps.md` for the failure it prevents.

## Parallel workers and shared files

Fresh-context workers may run in parallel, but **only on disjoint files**. Two workers editing one
file - above all a shared end-to-end test such as `ScreenFlowJvmTest.kt` - produce interleaved hunks
that cannot be attributed to a single item, and each sees the other's half-finished edit as a
compile failure. Hard-won rules:

- **Group items by file before dispatching.** One worker per file per batch; split a file's items
  across batches, never across simultaneous workers.
- **Prefer a new focused test file** over editing a shared one. Touch a shared test only when the
  item is genuinely about the flow it pins, and keep the change to a single hunk if you can.
- **Workers leave the tree dirty; the orchestrator stages, verifies and commits.** A worker that
  commits cannot see the other workers' in-flight changes, and its commit will not compile.
- **Check `git status` before committing.** A worker occasionally leaves a scratch or diagnostic
  test behind (a `ZzDiagTest`-style file); it must never reach a commit.
- **Verify once, after the batch**, not per worker, and read the counts from the result XML rather
  than trusting a log tail.

## Why this finishes a 30-item list

- The agent's context is only ever as large as **one item**.
- Progress is visible in `git log` and `backlog.json`, so a new session resumes exactly.
- A session ending is a non-event: the queue is on disk, not in the conversation.
- Because each item must have a check, "done" means verified, not "looks finished".

## Item shape

```jsonc
{
  "id": "UX-014",
  "title": "Short imperative summary",
  "severity": "high",              // high | medium | low
  "area": "editor",                // free-form grouping (screen, module, flow)
  "problem": "What is wrong, observed. Cite evidence.",
  "evidence": ["frames/editor/02-selected.png"],
  "acceptance": "The check that must pass. Concrete and binary.",
  "check": "gradlew :app:testDebugUnitTest",   // command, or a capture path
  "touch": ["app/src/main/java/.../EditorRoute.kt"],
  "status": "open",                // open | fixed | blocked | wontfix
  "commit": null,
  "verified": null,
  "note": null
}
```

Rules for a good item:

- **One behaviour.** If the acceptance needs "and", split it.
- **Binary acceptance.** "Readable" is not a check; "no node extends past the safe area" is.
- **Evidence or it did not happen.** Cite a frame, a failing test name, or a log line.

## What this is not

- Not a plan generator. The queue is created once (e.g. from a visual review) and then consumed.
- Not a place to hide failures. Blocked items stay visible with the reason.
- Not a substitute for a human verdict on "is this good UX". The queue proves the check passed;
  a person still decides whether it feels right.

## Adopting it

Copy `templates/agent-work-queue/` into a project, or run
`scripts/install-agent-work-queue.ps1 -ProjectPath <dir>` which scaffolds `agent/backlog.json`,
`agent/backlog.schema.json` and the `next-issue` helper, and installs the `ux-issue` OpenCode
command globally.
