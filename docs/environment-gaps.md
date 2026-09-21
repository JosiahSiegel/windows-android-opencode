# Environment gaps

How to handle "the check could not run" so it is fixed once for every future session and project,
instead of being worked around each time.

## The failure mode this prevents

An agent runs a project's own verification and it fails for a reason that is not the code:

```
python3 tools/verify.py fast
  -> python3: command not found
```

The tempting responses are all wrong:

- skip the check and report the change as done,
- substitute a made-up check that happens to pass,
- install a one-off interpreter by hand in the working directory,
- note it in the chat and move on.

Each leaves the next session - and the next project - in exactly the same hole. This is
**shift-left for the environment**: an error the agent hits at task time is really a defect in the
machine's provisioning, and that is where it should be fixed.

## The rule

> If a required check cannot run, that is an **environment gap**, not a reason to skip the check.
> Record it, fix the provisioner, verify the provisioner, then resume.

Corollaries:

- The **provisioner** (`scripts/install-toolchain.ps1`) is the single source of truth for the
  machine. Fixes belong there, never in a project's working tree.
- The **verifier** (`scripts/verify-setup.ps1`) must detect the gap and print the exact fix, so it
  is found at the start of a session rather than in the middle of a task.
- A check that could not run is reported as **NOT EVALUATED**, never as passing. (See also
  `docs/agent-work-queue.md` - the same honesty rule governs queue items.)

## The loop

1. **Recognise.** A check exits non-zero for an environmental reason, or a tool is absent. The
   agent records the exact command and the exact error.
2. **Classify.** Environment (missing tool, bad PATH, no device, network) versus code (the change
   is wrong). Only environment gaps come here.
3. **Record.** Add an item to the machine queue: what is missing, the command that fails, and the
   intended provisioning fix.
4. **Resolve in the provisioner.** Extend `install-toolchain.ps1` so a fresh machine gets the tool
   (portable, user-scoped, no admin where possible). Never a hand-install.
5. **Detect.** Add or extend a check in `verify-setup.ps1` that names the tool and the fix.
6. **Verify.** Run `verify-setup.ps1` on the machine and confirm the item now passes. Only then
   close it.
7. **Resume** the original work with the real check.

## Worked example: `python3`

Project tooling is invoked as `python3 tools/verify.py fast`. Windows ships no `python3`, so on a
bare machine that check was unrunnable.

- **Recognised** by a worker that ran `./gradlew.bat :app:testDebugUnitTest` but could not run the
  project's canonical `verify.py` and reported it rather than pretending.
- **Resolved** by provisioning a portable embeddable Python 3 into `<ToolchainRoot>\python` and a
  `python3` shim in `<ToolchainRoot>\bin` (added to the user PATH) in `install-toolchain.ps1`.
- **Detected** by the `python3 (project tooling)` check in `verify-setup.ps1`, which prints the
  exact remediation when it is missing.

## What belongs here

| Environment gap | Where it is fixed |
|---|---|
| Missing interpreter/CLI a project shells out to (python3, node, git) | `install-toolchain.ps1` + a `verify-setup.ps1` check |
| Stray quote or duplicate in PATH | `repair-path-quotes.ps1` |
| No emulator / no hypervisor | `install-toolchain.ps1`; WHPX is the one admin step |
| Slow builds | `add-defender-exclusions.ps1` |
| Project source is wrong | not here - that is a code item |

## Why this is worth the ceremony

It is the difference between a machine that gets slightly better every session and one where every
session rediscoveries the same missing tool. It also keeps the agent honest: "could not run" has a
defined home, so it never has to become "passed".
