# OpenCode V2 + native Windows Android setup plan

> **Appendix.** This is the original chronological record of provisioning one specific machine,
> including dead ends and open questions. It is the evidence behind `../README.md`, and it contains
> machine-specific paths. Read the README first; treat this as history rather than instructions.

Created 2026-09-21. Target: end-to-end Android development, testing, release, and publication
using OpenCode V2 on native Windows, with projects under `D:\repos`.

This plan deliberately discards assumptions from the previous `photo_print_sheets_app` tree
(developed with a WSL container, KVM emulator, and Linux toolchain). Everything below assumes
native Windows.

---

## 0. Decisions and scope

| Decision | Value |
|---|---|
| Harness | OpenCode **V2** (docs at `https://opencode.ai/v2/docs/`) |
| OS | Native Windows, x64 (AMD64) |
| OpenCode install method | Standalone binary (WinGet/npm are **not** supported for V2) |
| Repo root | `D:\repos` |
| Emulator acceleration | **WHPX** (not AEHD — it sunsets 2026-12-31) |
| Release builds | Signed + published on a Linux CI runner, not on Windows |

### Two facts that drive the whole plan

1. **V1 plugin implementations do not run in V2.** A plugin must default-export
   `Plugin.define({ id, setup(ctx) })`. A check of 25 popular community plugins found only
   `opencode-workflow-guard` and `opencode-oceanus` shipping a V2 entrypoint. The V2 plugin
   ecosystem is currently near-empty.
2. **V2 does not run language servers.** It preserves `lsp` config but does not start servers,
   expose LSP tools, or produce diagnostics. Gradle and CLI linters become the only source of
   compile/type truth.

---

## 1. State at time of writing

### Correction discovered mid-session

The harness hosting the session is **OpenCode Desktop 2.0.12**, not the WinGet CLI. Desktop
bundles its own CLI at `resources\opencode-cli.exe` (`opencode-cli.version` = 2.0.12), so
**V2 was already in use before this plan was written**. The standalone `opencode` on `PATH` was
a separate, older V1 install. Consequences:

- The "switching to V2" framing was wrong — only the *standalone CLI* needed changing.
- Uninstalling the V1 CLI does **not** disturb the session; Desktop hosts it.

| Item | Status |
|---|---|
| Harness | **OpenCode Desktop 2.0.12** (`%LOCALAPPDATA%\Programs\@opencodedesktop\OpenCode.exe`) |
| Bundled CLI | `resources\opencode-cli.exe`, version 2.0.12 |
| Standalone CLI (was) | V1 `1.18.29` via WinGet — unused by the session |
| Standalone CLI (now) | V2 `2.0.12` at `D:\repos\opencode-v2\2.0.12\opencode.exe`, first on user `PATH` |
| Global config | `C:\Users\<you>\.config\opencode\opencode.json` — still V1 shape |
| Global plugins | `oh-my-openagent`, `opencode-models-discovery` — both V1-only, inert under V2 |
| Java / JDK | **absent** |
| `adb` / Android SDK | **absent** — all of it lived in WSL |
| Node / npm | v26.4.0 / 11.17.0 |
| Git | 2.55.0 (git-bash available, so `bash` remains the shell) |
| Arch | AMD64 (x64) |

Note: the docs install page listed **2.0.6**, which is stale. **2.0.12** is current (2.0.13
returns HTTP 404) and matches the Desktop build.

---

## Phase 1 — Standalone CLI → V2 2.0.12 — DONE

The original plan said "install V2, remove V1". Discovery showed V2 was already running as
Desktop 2.0.12, so this phase reduced to aligning the *standalone CLI*.

- [x] Confirmed harness: OpenCode Desktop **2.0.12**, bundling CLI 2.0.12
- [x] Downloaded standalone `opencode-windows-x64.zip` — first as 2.0.6 (stale, taken from the
      docs install page), then corrected to **2.0.12**
- [x] Extracted to `D:\repos\opencode-v2\2.0.12\opencode.exe`
- [x] Prepended `D:\repos\opencode-v2\2.0.12` to the **user** `PATH`
      - Original PATH backed up to `D:\repos\opencode-v2\user-path-backup.txt`
      - Reversible: restore that value into the user `Path` variable
- [x] Verified fresh-terminal resolution: `(Get-Command opencode).Source` →
      `D:\repos\opencode-v2\2.0.12\opencode.exe` and `opencode --version` → `opencode v2.0.12`
- [x] Verified V2 loads the existing V1-shaped config without error using
      `opencode debug paths` (reports config dir `C:\Users\<you>\.config\opencode`)
- [x] Removed the stale 2.0.6 build and both installers, reclaiming ~180 MB
- [ ] Remove the unused V1 CLI — safe now, since it does not host the session:
      - `winget list opencode` to get the exact package ID
      - `winget uninstall <ID>`
      - then confirm `(Get-Command opencode).Source` still points at the V2 path
- [ ] Optional: leave `update` at its default so the standalone CLI self-updates and does not
      drift behind Desktop again

> V2 CLI and Desktop update independently. Keeping them near the same version avoids confusing
> behaviour differences; the version-check methods differ between the two.
>
> First V2 terminal-client startup auto-migrates `tui.json` settings into the new global
> `cli.json`. That is expected and leaves the V1 `tui.json` unchanged.

---

## Phase 2 — Migrate configuration to native V2

V2 reads existing V1 config from the same locations and normalizes it in memory without
rewriting the file, so this phase is **optional**. Conversions do not need to happen at once,
and V1 and V2 fields may coexist at the top level.

### 2a. Recommended path for the permission file — do NOT hand-convert

V1 groups permission effects by tool and pattern object; V2 uses **one ordered `permissions`
array** where the last matching rule wins. A careless conversion silently changes policy
precedence. For a config whose whole point is protecting keystores and blocking release
commands, that is the wrong failure mode.

Instead: let OpenCode perform it, then diff the result against the original:

```
Migrate my OpenCode configuration, including file-based definitions, from the V1 format to the
native V2 format. Preserve its behavior and all unrelated settings.
```

Keep a copy of the V1 files until the migrated behavior is verified.

### 2b. Global config rename table

| V1 | V2 |
|---|---|
| `plugin` | `plugins` (array; tuple form becomes `{ package, options }`) |
| `provider` | `providers` |
| provider `npm` | `package` (AI SDK packages take an `aisdk:` prefix) |
| provider `options.baseURL` | `settings.baseURL` |
| provider `options.*` | split across `settings` / `headers` / `body` |
| model `context` / `output` | `limit.context` / `limit.output` |
| model `modalities` | `capabilities.input` / `capabilities.output` |
| model `tool_call` | `capabilities.tools` |
| model `options` | `settings` |
| model `status: "deprecated"` | `disabled: true` |
| model `cache_read` / `cache_write` | `cache.read` / `cache.write` |
| `variants` object | `variants` array, each entry with an `id` |
| `compaction.reserved` | `compaction.buffer` |
| `compaction.preserve_recent_tokens` | `compaction.keep.tokens` |
| `compaction.prune` / `tail_turns` | **ignored in V2** (warning) |
| `attachment` | `media` |
| `snapshot` | `snapshots` |
| `autoshare` | `share` (`"manual"` / `"auto"` / `"disabled"`) |
| `agent` / `mode` maps | `agents` (`prompt`→`system`, `disable`→`disabled`, `maxSteps`→`steps`, `model`+`variant`→`model#variant`) |
| `command` | `commands` (`subtask`→`subagent`) |
| `reference` | `references` |
| `permission` object | `permissions` array |
| permission action `bash` | `shell` |
| permission action `task` | `subagent` |
| permission action `write` / `patch` | `edit` |
| skill `paths` + `urls` | one `skills` array |
| `mcp.<name>` | `mcp.servers.<name>` |
| mcp `enabled: true` | `disabled: false` |
| mcp numeric `timeout` | `timeout: { catalog, execution }` |
| `logLevel` | env var `OPENCODE_LOG_LEVEL` |
| `lsp` | preserved but **inactive** |

Unchanged and still valid: `$schema`, `model`, `default_agent`, `shell`, `watcher`, `formatter`,
`instructions`, `tool_output`.

### 2c. Target global config (native V2 shape)

Illustrative conversion of the current global file. Reconcile against the migrated output —
do not paste blind.

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [],
  // Historical example only: this provider block was later removed after the owner confirmed they
  // use the built-in DeepSeek provider, which needs no custom provider entry.
  "providers": {
    "selfHosted": {
      "name": "selfHosted",
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": {
        "baseURL": "https://<your-openai-compatible-endpoint>/v1"
      },
      "models": {
        "deep": {
          "name": "deep",
          "limit": { "context": 250000, "output": 8192 },
          "headers": { "x-manifest-tier": "deep" },
          "capabilities": { "tools": true, "input": ["text", "image", "pdf"], "output": ["text"] }
        },
        "orchestrate": {
          "name": "orchestrate",
          "limit": { "context": 250000, "output": 8192 },
          "headers": { "x-manifest-tier": "orchestrate" },
          "capabilities": { "tools": true, "input": ["text"], "output": ["text"] }
        },
        "quick": {
          "name": "quick",
          "limit": { "context": 250000, "output": 8192 },
          "headers": { "x-manifest-tier": "quick" },
          "capabilities": { "tools": true, "input": ["text", "image", "pdf"], "output": ["text"] }
        },
        "visual": {
          "name": "visual",
          "limit": { "context": 250000, "output": 8192 },
          "headers": { "x-manifest-tier": "visual" },
          "capabilities": {
            "tools": true,
            "input": ["text", "image", "pdf", "audio", "video"],
            "output": ["text"]
          }
        }
      }
    }
  },
  "compaction": {
    "auto": true,
    "buffer": 20000,
    "keep": { "tokens": 8000 }
  },
  "shell": "bash"
}
```

Notes and uncertainties:

- `@opencode/ai/providers/openai-compatible` is the native V2 package named in the Models doc.
  `aisdk:@ai-sdk/openai-compatible` is the migration-guide equivalent that preserves the exact
  old package. Either is defensible; the native one is preferred.
- In the V1 file `compaction` sits **inside** the provider object. The migration guide documents
  it as a **top-level** field. Move it to the top level and verify.
- `keep.tokens` is a retained-context budget; pick a value based on real usage. V2 has no
  `prune` equivalent — it uses checkpoint-based compaction instead.
- `capabilities.output` did not exist in V1 (`modalities` carried input only), so `["text"]`
  is an inference, not a conversion.

### 2d. Plugin entries

- [ ] Drop `oh-my-openagent@latest` — V1-only, will not run in V2. Keep it only if/when a
      `@opencode/plugin`-based release appears.
- [ ] Drop `opencode-models-discovery` — V1-only. V2 discovers Ollama, LM Studio, and vLLM
      natively, and supports a manual OpenAI-compatible provider (which this config already is).
- [ ] Use `plugins` (plural) for anything new, or rely on automatic discovery from
      `.opencode/plugins/` and `~/.config/opencode/plugins/`.

---

## Phase 3 — Android toolchain — COMPLETE (2026-09-21)

Installed with **no admin rights**, using a portable JDK and a user-scoped SDK. No Android Studio.

- [x] JDK: Temurin **21.0.12.1+1 LTS** portable zip → `D:\toolchains\jdk-<version>`
      (fetched from the Adoptium API; MSI installers would have required elevation, so the zip
      route was used instead)
- [x] `cmdline-tools` build **15859902** → `%LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest`
- [x] User environment variables set:
      - `JAVA_HOME` = `D:\toolchains\jdk-<version>`
      - `ANDROID_HOME` = `%LOCALAPPDATA%\Android\Sdk`
      - `PATH` += `%JAVA_HOME%\bin`, `%ANDROID_HOME%\cmdline-tools\latest\bin`,
        `%ANDROID_HOME%\platform-tools`, `%ANDROID_HOME%\emulator`
- [x] Licences accepted: `yes | sdkmanager --licenses`
- [x] Packages installed:
      - `platform-tools` 37.0.1 (adb 1.0.41)
      - `build-tools;36.1.0`
      - `platforms;android-36`
      - `emulator` 37.1.11
      - `system-images;android-36;google_apis;x86_64`
- [ ] Windows Defender exclusions for `~\.gradle`, build directories and the AVD directory —
      **needs admin**, still outstanding
- [ ] Optional: install Android Studio later if an IDE is wanted; it coexists fine

Footprint: SDK ~5.8 GB at `%LOCALAPPDATA%\Android\Sdk`; JDK ~330 MB at `D:\toolchains`.

> `sdkmanager` now prints a deprecation warning pointing at a newer, agent-oriented **Android CLI**
> (`android sdk`, see `d.android.com/tools/agents/android-cli`). Worth evaluating later;
> `sdkmanager` still works today.

---

## Phase 4 — Emulator and virtualization — COMPLETE (2026-09-21)

- [x] WHPX was **already installed and usable** — no admin action or reboot was needed:
      `emulator -accel-check` → `WHPX(10.0.26200) is installed and usable`
- [x] AVD created: `pixel_api36` (Pixel 7, Android 16 / API 36, `google_apis`, x86_64) at
      `C:\Users\<you>\.android\avd\pixel_api36.avd`
- [x] Boot verified end-to-end, headless: `sys.boot_completed=1`, `adb devices` → `emulator-5554`,
      `ro.build.version.release` → `16`, then a clean `adb emu kill`
- [x] Note: `avdmanager` prints a harmless `Could not load devices.xml` warning during creation;
      the AVD is still created correctly

Why WHPX and not AEHD:

- Android documents **WHPX as the recommended** accelerator on Windows.
- **AEHD sunsets 2026-12-31** — roughly three months away.
- AEHD **requires Hyper-V to be disabled**, so it also rules out WSL2 and Docker Desktop.
- HAXM is removed from the emulator entirely.

Known issue to watch: the emulator release notes record a **guest kernel crash after quick boot for
API 36 and 35 on Windows 11 with WHPX** on some CPUs. Boot is verified working on this machine; if a
boot ever hangs, disable quick boot before assuming a deeper fault.

---

## Phase 5 — What to actually add to OpenCode

### 5a. MCP servers (the durable integration layer)

MCP is **not** affected by the V2 plugin break, so this is where effort pays off.

```bash
opencode mcp add mobile -- npx -y @mobilenext/mobile-mcp
opencode mcp add playwright -- npx -y @playwright/mcp@latest
opencode mcp list
```

| Server | Use | Notes |
|---|---|---|
| `agent-device` | Android/iOS automation + verification (CLI + MCP) | Callstack, MIT, no deps |
| `@mobilenext/mobile-mcp` | ADB + accessibility-tree UI driving | Apache-2.0 |
| `appium-mcp` | Durable E2E test authoring | Official Appium org |
| `scrcpy-mcp` | Screen vision + tap/swipe | Low adoption; pairs with screenshot evidence |
| `@playwright/mcp` | WebView and web service boundary | Microsoft, very widely used |
| `chrome-devtools-mcp` | Performance traces, network, console | Google |

MCP config lives under `mcp.servers` in V2. Local servers use `type: "local"` and a `command`
array; disable with `disabled: true` (not `enabled`).

Review the source before letting any of these drive your emulator — they execute code and
receive device screenshots.

### 5b. Plugins — write local, don't hunt

Given only two V2-capable community plugins were found, prefer a small local plugin for
project-specific guards. Create `.opencode/plugins/<name>/index.ts`:

```ts
import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "android.guards",
  async setup(ctx) {
    await ctx.tool.hook("execute.before", (event) => {
      const input = event.input as { command?: string }
      if (event.tool === "shell" && /\b(bundleRelease|publish|signingReport)\b/i.test(input.command ?? "")) {
        throw new Error("Release/signing commands require explicit owner authorization")
      }
    })
  },
})
```

Useful V2 surface for Android work: `ctx.tool.transform` (custom tasks), `ctx.tool.hook`
(`execute.before` / `execute.after`), `ctx.command.transform` (e.g. a `verify` command),
`ctx.shell.hook("create.before")` (env injection), `ctx.event.subscribe()`, `ctx.storage`.
See `https://opencode.ai/v2/docs/build/plugins`.

### 5c. Skills, agents, commands

Discovery paths in V2 (all discovered automatically):

```
.opencode/skills/<skill-id>/SKILL.md     # move whole skill dirs, not just SKILL.md
.opencode/agents/<name>.md               # V2-preferred; agent/ still discovered
.opencode/commands/<name>.md             # V2-preferred; command/ still discovered
```

V1 `skill/`, `agent/`, `mode/`, `command/` directories still work. Converting frontmatter is
optional: `prompt`→`system`, `disable`→`disabled`, `permission`→`permissions`,
`model`+`variant`→`model#variant`, `subtask`→`subagent`.

### 5d. Replacing LSP

Because V2 runs no language servers, make the build the source of truth:

- `gradlew.bat` tasks: `compileDebugKotlin`, `lint`, `test`, `connectedDebugAndroidTest`
- `ktlint` / `detekt` as Gradle plugins, run via the shell, wired into hooks if desired
- Keep `formatter` config for file-level formatting

---

## Phase 6 — Release and publication

Architecture: **build and test locally on Windows; sign and publish on Linux CI.**

- [ ] Signing: create an upload keystore; wire `signingConfigs` from environment variables
      (never commit the keystore or passwords). Verify artifacts with
      `apkanalyzer debuggable=false` and `apksigner verify`.
- [ ] Publication: prefer **Gradle Play Publisher** (`com.github.triplet.play`) over fastlane —
      fastlane needs Ruby and is awkward on Windows.
- [ ] CI: GitHub Actions on a Linux runner holding the Play service account secret, running
      `bundleRelease` and the upload step. This avoids Windows signing quirks and keeps the
      release credential out of the agent's reach.
- [ ] Keep `release-candidate`-style checks honest: a green local build is not a release, and a
      branch push is not a publish.

---

## Phase 7 — Windows-specific gotchas

- **`gradlew.bat`**, not `./gradlew`. In bash, prefer `./gradlew.bat` explicitly.
- **Long paths**: `git config --global core.longpaths true` and enable the Windows long-path
  policy.
- **Line endings**: add a `.gitattributes` (`* text=auto`, `*.bat text eol=crlf`,
  `*.sh text eol=lf`, `gradlew text eol=lf`).
- **Gradle file locks**: `gradlew.bat --stop` to release daemons.
- **One adb server only**: after leaving WSL, run `adb kill-server` once. A stale WSL adb
  competing for port 5037 produces confusing device lists.
- **Antivirus** exclusions for Gradle caches and AVD directories.
- **Keep repos off synced folders** (OneDrive et al.) — you already use `D:\repos`, which is
  correct.

---

## Verification checklist

- [ ] `opencode --version` reports 2.x and `opencode api get /api/info` succeeds
- [ ] `opencode mcp list` shows every configured server `connected`
- [ ] `java -version`, `adb version`, `sdkmanager --list_installed` all work
- [ ] `emulator -accel-check` reports WHPX usable
- [ ] A debug APK builds and installs: `gradlew.bat :app:assembleDebug` then `adb install -r ...`
- [ ] Instrumented tests run on the emulator
- [ ] A migrated-config diff shows no unintended permission or provider changes
- [ ] No V1-only plugin remains in `plugins`

---

## Trade-offs and open questions

**What gets worse moving to V2**

- `oh-my-openagent` and `opencode-models-discovery` stop working (V1-only).
- All LSP diagnostics disappear; compile/lint feedback now comes only from Gradle runs.
- The community plugin ecosystem is thin and mostly incompatible today.

**What carries over cleanly**

- Config locations, `AGENTS.md` instructions, skills, agents, commands, MCP servers, models,
  and providers.

**Open questions to resolve during rollout**

1. Whether `@opencode/ai/providers/openai-compatible` or `aisdk:@ai-sdk/openai-compatible` is
   correct for the self-hosted endpoint — confirm at runtime.
2. Whether V2 accepts `compaction` nested under a provider, or requires it top-level.
3. Whether `external_directory` remains a permission action in V2, or is folded into `read`.
   Do not guess — let the migration produce it and read the result.
4. Whether API 36 + WHPX quick boot is stable on this specific CPU.
5. Whether any currently relied-upon V1 plugin is load-bearing enough to justify staying on
   1.18.29 longer.

*(Resolved: V1 is removed and the plugins were not load-bearing. See below.)*

---

## Phase 2 — Configuration migration — COMPLETE (2026-09-21)

`~/.config/opencode/opencode.json` converted to native V2 shape:

- `plugin` → `plugins` (now empty; `oh-my-openagent` and `opencode-models-discovery` were V1-only
  and cannot run under V2)
- `provider` → `providers`; `npm` → `package: "aisdk:@ai-sdk/openai-compatible"` (the documented
  1:1 mapping from the migration guide); `options.baseURL` → `settings.baseURL`
- model `context` / `output` → `limit.context` / `limit.output`; `modalities.input` →
  `capabilities.input`
- provider-nested `compaction` → top level; `reserved` → `buffer`; `prune` dropped (no V2
  equivalent)
- added a global `permissions` deny-list: reads of `**/*.jks`, `**/*.keystore`, `**/*.pepk` and
  `**/keystore.properties`, plus shell commands matching `*bundleRelease*` and `*publish*`
- `shell: "bash"` unchanged

Verification: `opencode models` and `opencode run --model selfHosted/quick` behave **identically**
under the V1 and V2 configs, so the conversion is behaviour-preserving. Caveat: `selfHosted` is
absent from the CLI model list and returns `Model unavailable` under **both** shapes, so this is
not a migration regression — the CLI simply cannot see that provider.

**Resolved:** the owner confirmed the provider was unused; it has been removed from the global
config.

Backup retained: `~/.config/opencode/opencode.json.v1-backup-20260921-103708`. Also removed on
request: the V1 CLI (`winget uninstall SST.opencode`) and stale V1 config backups.

---

## Android CLI adoption — 2026-09-21

`sdkmanager` is deprecated in favour of an agent-oriented **Android CLI** (`android`). Adopted:

- `android init` installed Google's official `android-cli` skill into the OpenCode skills directory
- `android skills add --all --agent=opencode` installed **24 official Google Android skills**:
  `adaptive`, `agp-9-upgrade`, `android-cli`, `android-intent-security`, `android-profiler`,
  `appfunctions`, `camerax`, `display-glasses-with-jetpack-compose-glimmer`, `edge-to-edge`,
  `engage-sdk-integration`, `leanback-to-compose-tv-migration`, `media3-cast-integration`,
  `migrate-xml-views-to-jetpack-compose`, `ml-kit-genai-prompt-api`, `navigation-3`,
  `navigation-event`, `play-billing-library-version-upgrade`, `play-policy-insights`, `r8-analyzer`,
  `restore-credentials`, `styles`, `testing-setup`, `verified-email`, `wear-compose-m3`
- `AGENTS.md` and the three hand-written skills updated to prefer Android CLI commands

Why this matters: Android CLI restores capability that V2 removed. `android studio analyze-file`,
`find-declaration`, `find-usages` and `render-compose-preview` give semantic code analysis and
Compose preview rendering, substituting for the language-server support V2 does not provide.
`android create` also replaces the planned Layer 3 project template.

Limitations:

- **`android emulator` is disabled on Windows** — AVD lifecycle stays on `emulator` / `avdmanager`
- `android studio *` requires a running Android Studio instance with Gemini enabled
- Android CLI collects usage metrics unless disabled

### Deprecation addressed

- [x] Confirmed no skill or instruction tells the agent to use `sdkmanager` any more
- [x] `android sdk` verified as a working replacement (`android sdk list --all` reports every
      installed package correctly in the new `platforms/android-36` slash syntax)
- [x] `android` resolves on `PATH` via `%ANDROID_HOME%\cmdline-tools\latest\bin\android.exe`
      (a launcher that bootstraps the real CLI)
- [x] `android update` run — already current at **1.0.16261425**
- [x] `%USERPROFILE%\.androidrc` created with `--no-metrics` and `--sdk=<ANDROID_HOME>`, verified
      honoured by running `android info` and `android sdk list` with no flags
- [x] `android init` installed Google's official `android-cli` skill; `android skills add --all
      --agent=opencode` installed the full official skill set and can refresh it later

Notes:

- The real CLI binary is `%USERPROFILE%\.android\bin\android-cli.exe`; runtime state lives under
  `%USERPROFILE%\.android\cli` (bundles, skills, analytics, update check).
- The `cmdline-tools` package is still required because that is where Google ships the `android`
  launcher, and because `avdmanager` is used for AVDs on Windows. `sdk list` reports an available
  cmdline-tools update (23.0.0); this is optional now that `sdkmanager` is no longer used.
- Do not "fix" the deprecation by deleting `sdkmanager` — it shares a directory with the `android`
  launcher and is harmless.

---

## Still outstanding

1. **Defender exclusions** for `~\.gradle`, build directories and the AVD directory — the only
   admin-gated item, and the largest single build-speed win on Windows
2. **MCP servers** — consider `mobile-mcp` / `appium-mcp` / `playwright` as global servers
3. ~~**Optional cleanup**~~ — **done**: removed ~57 MB of V1 plugin dependencies, reset
   `package.json` to empty dependencies, and consolidated config backups
4. **Evaluate** `android studio *` commands once Android Studio is installed, if an IDE is wanted

---

## Pinnacle pass — 2026-09-21

### Stale project neutralised

`photo_print_sheets_app` carried WSL-era OpenCode config that would silently override the global
layer (project config beats global) while assuming Linux, KVM and `gradlew`. Archived in place and
recoverable with one command:

| Was | Now |
|---|---|
| `.opencode/` | `.opencode.wsl-archived/` |
| `opencode.json` | `opencode.json.wsl-archived` |
| `AGENTS.md` | `AGENTS.md.wsl-archived` |

Verified: `opencode debug config` inside that directory now resolves **only** the global sources.
Undo with `git checkout -- .` in the repository (it was clean before the change).

### MCP servers

Added globally and confirmed connected:

| Server | Purpose | Status |
|---|---|---|
| `mobile` (`@mobilenext/mobile-mcp`) | Android device control, UI tree, screenshots | connected, 32 tools |
| `playwright` (`@playwright/mcp`) | Web and WebView automation | connected, 25 tools |

### Gradle tuning

`%USERPROFILE%\.gradle\gradle.properties` created: 4 GB daemon heap, parallel builds, build cache,
Kotlin daemon heap, and `org.gradle.java.home` pinned to the Temurin 21 install. Verified in use —
Gradle reports `Daemon JVM: D:\toolchains\jdk-<version> (from org.gradle.java.home)`.

### Project template — `D:\repos\android-template`

Scaffolded with `android create` so it always matches current Android defaults, then enhanced:

- ktlint 14.2.0 wired through the version catalog
- `.editorconfig` with two deliberate, documented ktlint adjustments (below)
- Android Lint block plus environment-driven release `signingConfigs` that cannot break debug builds
- `.gitattributes`, `.github/workflows/android.yml` (build/lint/test on Linux, manual signed release)
- `README.md` documenting the golden path
- Initialised as a git repository with one commit (45 files)

Verified green: `:app:compileDebugKotlin`, `:app:ktlintCheck`, `:app:lintDebug`,
`:app:testDebugUnitTest`, `:app:assembleDebug`. End-to-end device proof: deployed to `pixel_api36`,
launched, and `android layout` returned `Hello Android!`.

Two ktlint adjustments, both deliberate and recorded in `.editorconfig`:

1. `ktlint_function_naming_ignore_when_annotated_with = Composable` — Compose uses PascalCase,
   which conflicts with ktlint's camelCase default. Scoped to `@Composable` only.
2. `ktlint_standard_filename = disabled` — this rule fires while `NavigationKeys.kt` holds a single
   declaration and is purely stylistic.

### Environment defect found and fixed

The machine-level PATH contained a malformed entry, `C:\Program Files\GitHub CLI"`, with a stray
double quote. That breaks any Java tooling building a space-separated command line; the symptom was
`Could not find or load main class Files\GitHub`. Pre-existing and machine-wide, not caused by this
setup.

`fix-machine-path.ps1` was written to this directory and **run by the owner with elevation**.
Independently verified afterwards:

- No machine or user PATH entry contains a quote; the `GitHub CLI` entries are now clean
- `:app:testDebugUnitTest --rerun` (forcing real execution, fresh environment, no workaround)
  completed `BUILD SUCCESSFUL` with **2 tests, 0 failures, 0 errors**

### Provider config corrected

`selfHosted` was removed from the global config; the owner uses the built-in DeepSeek provider,
which needs no custom provider entry. Backup at `opencode.json.bak-pre-selfhosted-removal`.
Verified afterwards: `opencode models` resolves `deepseek/*` models and all agents and MCP servers
still load. Config keys are now `$schema, plugins, compaction, shell, permissions, mcp`.

### Emulator reliability note

The headless software-rendered emulator raised a "System UI isn't responding" ANR under heavy load
while Gradle was also building. That is an emulator-side symptom, not an app or setup defect.
Dismiss it with `adb shell input tap <x> <y>` on "Wait", or reboot the AVD. Documented in the
template README and the `android-emulator` skill.

### Owner actions — completed

1. ~~Run `fix-machine-path.ps1` elevated~~ — **done**, verified by a forced test re-run
2. ~~Run `add-defender-exclusions.ps1` elevated~~ — **done**. Note: Defender exclusions cannot be
   read back without elevation, so they were not independently verified from this session. Confirm
   with `Get-MpPreference | Select-Object -ExpandProperty ExclusionPath` in an elevated shell.
3. ~~Confirm `selfHosted`~~ — disregarded; the provider was unused and has been removed

### Remaining optional work

- ~~Dead V1 plugin dependencies~~ — removed; the config directory is now 4.4 MB
- `tui.json` remains as a V1-era file that V2 auto-migrates into `cli.json`; left in place
  deliberately because it is an OpenCode-managed migration input
- Install Android Studio if an IDE is wanted; it will then enable the `android studio *` commands
  (`analyze-file`, `find-usages`, `render-compose-preview`) that substitute for V2's missing LSP
- Consider scoping the 27 global skills if they add noise in non-Android projects
