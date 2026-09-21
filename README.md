# OpenCode + Android on Windows

A reproducible, administrator-light setup for **native Windows Android development driven by
OpenCode**. Written so it can be applied to a new machine, re-applied to a broken one, or read as a
reference when something misbehaves.

Everything here was derived by actually provisioning a machine and verifying each layer, not by
summarising documentation. Where a claim is version-specific or uncertain, it says so.

---

## What you get

| Layer | Result |
|---|---|
| JDK | Temurin 21 LTS, portable zip (no MSI, no elevation) |
| Android SDK | `platform-tools`, `build-tools`, a platform, `emulator`, an x86_64 system image |
| Emulator | One reusable AVD, WHPX-accelerated |
| Android CLI | Google's agent-oriented `android` command, metrics disabled |
| OpenCode | V2 CLI plus the official Android skills Google ships |
| MCP | Optional Android device control and browser automation |
| Build tuning | Global Gradle heap, parallel and caching defaults |
| Verification | A script that checks every layer and reports PASS / WARN / FAIL |

**Requirements:** Windows 10 1803+ or Windows 11, x64 (or ARM with the matching binaries), ~6 GB of
free disk, and a normal user account. Administrator rights are needed **once**, for emulator
acceleration only.

---

## How this repo relates to your projects

This repo is a **bootstrap and a toolbox**, not a runtime dependency.

**Provisioning is one-time and machine-wide.** Once `install-toolchain.ps1` has run, everything your
projects need lives outside this repo:

| What | Where |
|---|---|
| JDK | wherever `JAVA_HOME` points (set by the install script; override with `-ToolchainRoot`) |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk` |
| `JAVA_HOME`, `ANDROID_HOME`, `PATH` | user environment variables |
| Android CLI defaults | `%USERPROFILE%\.androidrc` |
| Gradle tuning | `%USERPROFILE%\.gradle\gradle.properties` |
| OpenCode config, instructions, skills, agents, MCP | `%USERPROFILE%\.config\opencode\` |

None of those point back at this repo, so **no project ever references it, and no project needs
anything copied from it.** Verified: a brand-new empty directory resolves only global OpenCode
configuration and receives the full agent, skill and MCP set with no per-project setup.

**What remains useful afterwards** are the two diagnostics, which is why the clone is worth keeping
somewhere convenient:

- `verify-setup.ps1` — re-run whenever a build breaks in a way that looks unrelated to the code
- `repair-path-quotes.ps1` — the PATH defect it detects can be reintroduced by any installer

The machine does not need this repo present. Only *you* might, and only to run those two.

**A project template is a different role.** A template repository *is* a recurring dependency by
design — it is the starting point for each new app. Do not confuse the two: this repo sets up the
machine; a template starts a project. (`android create` can generate a project without any template
at all, which is often the better option since Google keeps its template current.)

---

## Quick start

```powershell
# from your clone of this repository
cd scripts

# 1. Provision the toolchain (no admin needed; idempotent, safe to re-run)
.\install-toolchain.ps1
```

Open a **new** terminal so the updated environment is inherited, then:

```powershell
# 2. Confirm every layer, including the JDK, SDK, emulator, Android CLI and OpenCode
.\verify-setup.ps1
```

`install-toolchain.ps1 -DryRun` prints exactly what it would do without downloading or changing
anything. Useful values to override:

```powershell
.\install-toolchain.ps1 -ApiLevel 35 -BuildTools 35.0.1 -AvdName pixel_api35
.\install-toolchain.ps1 -ToolchainRoot 'C:\tools' -SdkPath 'C:\Android\Sdk'
```

### The one administrator step

Emulator acceleration is machine-wide and needs elevation. **Enable the Windows Hypervisor Platform
(WHPX)**, which also requires Hyper-V:

1. Open *Turn Windows features on or off*
2. Enable **Hyper-V** and **Windows Hypervisor Platform**
3. Reboot
4. Confirm: `emulator -accel-check` should report `WHPX ... is installed and usable`

Do this **instead of** the Android Emulator hypervisor driver (AEHD). AEHD is deprecated — Google
sunset it on 2026-12-31 — and it requires Hyper-V to be *disabled*, which also rules out WSL2 and
Docker Desktop. Intel HAXM has been removed from the emulator entirely.

### Optional speed-up

```powershell
# elevated
.\add-defender-exclusions.ps1
```

Real-time scanning of Gradle caches, the SDK and the emulator is one of the largest avoidable
slowdowns for Android builds on Windows. The script derives the paths from `JAVA_HOME`,
`ANDROID_HOME` and your profile, so it needs no editing. It deliberately does **not** exclude your
repository root — that would exclude your source from scanning. Add `-IncludeRepositoryRoot` if you
accept that trade-off on a build machine.

---

## Enabling agents: OpenCode

### Install OpenCode V2 on Windows

Windows package managers are **not supported** for V2. Use the standalone binary or the desktop app:

- Standalone: download `opencode-windows-x64.zip` from `https://opencode.ai/files/bin/<version>/`
- Desktop: the `.exe` from the same page

V1 and V2 are not installed side by side by default. If a package-managed V1 exists, remove it
first (`opencode uninstall --keep-config --keep-data`, then `winget uninstall <id>` if WinGet was
the installer).

Verify: `opencode --version`, `opencode service status`, `opencode api get /api/info`.

### Two facts that cause most confusion

1. **V1 plugin implementations do not run in V2.** A plugin must default-export
   `Plugin.define({ id, setup(ctx) })`. Most community plugins were still V1-only at the time of
   writing, so check for a `@opencode/plugin` dependency before assuming a plugin works.
2. **V2 does not run language servers.** It accepts and preserves `lsp` configuration but does not
   start servers or produce diagnostics. Compile and lint output from Gradle is your only static
   signal — which is why the Android CLI below matters.

### Global configuration

`~/.config/opencode/opencode.json`. A minimal, working native-V2 config:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [],
  "compaction": { "auto": true, "buffer": 20000 },
  "shell": "bash",
  "permissions": [
    { "action": "read",  "resource": "**/*.jks",              "effect": "deny" },
    { "action": "read",  "resource": "**/*.keystore",         "effect": "deny" },
    { "action": "read",  "resource": "**/keystore.properties","effect": "deny" },
    { "action": "shell", "resource": "*bundleRelease*",       "effect": "deny" },
    { "action": "shell", "resource": "*publish*",             "effect": "deny" }
  ],
  "mcp": { "servers": {} }
}
```

Useful commands:

```bash
opencode debug config     # which config files are actually loaded
opencode debug agents     # every registered agent
opencode debug paths      # data, config, cache, log locations
opencode mcp list         # MCP connection status
```

### Migrating a V1 config

V2 reads V1 config and normalises it in memory, so conversion is optional. When converting:

| V1 | V2 |
|---|---|
| `plugin` | `plugins` (tuple becomes `{ package, options }`) |
| `provider` | `providers` |
| provider `npm` | `package` (AI SDK packages take an `aisdk:` prefix) |
| provider `options.baseURL` | `settings.baseURL` |
| model `context` / `output` | `limit.context` / `limit.output` |
| model `modalities` | `capabilities.input` / `capabilities.output` |
| `compaction.reserved` | `compaction.buffer` |
| `compaction.prune` / `tail_turns` | removed — no V2 equivalent |
| `permission` object | `permissions` array |
| permission action `bash` | `shell` |
| permission action `write` / `patch` | `edit` |
| permission action `task` | `subagent` |
| `mcp.<name>` | `mcp.servers.<name>` |
| mcp `enabled: true` | `disabled: false` |
| `agent` / `mode` | `agents` (`prompt`→`system`, `disable`→`disabled`) |
| `command` | `commands` (`subtask`→`subagent`) |
| `snapshot` / `attachment` | `snapshots` / `media` |

Do **not** hand-convert a permission-heavy config. V1 groups effects by tool and pattern object;
V2 uses one ordered array where the last matching rule wins, so a careless conversion silently
changes policy precedence. Let the agent migrate it and diff the result.

### Skills: get Google's, don't write your own

Google ships the `android` CLI built explicitly for agent workflows, and with it a library of
official Android skills:

```bash
android init                                  # installs the android-cli skill for detected agents
android skills list                           # what is available
android skills add --all --agent=opencode     # install all official skills for OpenCode
```

At the time of writing this installs 24 skills covering Compose adaptability, edge-to-edge,
Navigation 3, testing setup, R8 keep rules, Play policy, ML Kit, CameraX and more. Refresh them at
any point with the same command.

Install into the global skills directory (`~/.config/opencode/skills`) so every project inherits
them. Project-level `.opencode/skills` overrides global ones.

### MCP servers

MCP is unaffected by the V2 plugin break, so it is the durable integration layer:

```bash
opencode mcp add mobile     --global -- npx -y @mobilenext/mobile-mcp
opencode mcp add playwright --global -- npx -y @playwright/mcp@latest
opencode mcp list
```

Review third-party MCP servers before granting them device access; they execute code and receive
screenshots.

### Global Gradle tuning

`%USERPROFILE%\.gradle\gradle.properties` applies to every build on the machine:

```properties
org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8
org.gradle.parallel=true
org.gradle.caching=true
kotlin.daemon.jvmargs=-Xmx2g
```

Confirm it is in effect — Gradle prints the JDK it chose:

```
Daemon JVM: <path> (from org.gradle.java.home)
```

---

## The Android CLI

`sdkmanager` is deprecated in favour of the `android` command. It is a genuine upgrade for agent
work, and it restores capability that V2 removed:

| Task | Command |
|---|---|
| Scaffold a project from a template | `android create --name="My App" --output=<dir>` |
| List templates | `android create list --name=x` |
| Build targets and artifact paths | `android describe` |
| Install and launch an APK | `android run --apks=<path>` |
| UI layout tree as JSON | `android layout --pretty` |
| Screenshot | `android screen capture --output=ui.png` |
| Annotated screenshot + tap coordinates | `android screen capture --annotate -o ui.png` then `android screen resolve` |
| SDK packages | `android sdk install` / `list` / `update` / `remove` |
| Official docs | `android docs search "<query>"` then `android docs fetch kb://...` |
| Semantic code analysis | `android studio analyze-file`, `find-declaration`, `find-usages` |
| Compose preview rendering | `android studio render-compose-preview` |
| Dependency versions | `android studio version-lookup <artifact>` |

The `android studio *` commands require Android Studio to be running with Gemini enabled. They are
the closest available substitute for the language server support V2 does not have.

**Caveats:**

- **`android emulator` is disabled on Windows.** Manage AVDs with `emulator` and `avdmanager`.
- The CLI collects usage metrics. `%USERPROFILE%\.androidrc` disables that and pins the SDK:

  ```
  --no-metrics
  --sdk=C:\Users\<you>\AppData\Local\Android\Sdk
  ```

- Keep `cmdline-tools` installed even though `sdkmanager` is deprecated: it is where Google ships
  the `android` launcher, and it provides `avdmanager`.
- `android-cli.exe` itself lives in `%USERPROFILE%\.android\bin`; state is under
  `%USERPROFILE%\.android\cli`. Run `android update` occasionally.

---

## Daily workflow

```bash
./gradlew.bat :app:compileDebugKotlin        # fast compile check
./gradlew.bat :app:lintDebug                 # Android Lint
./gradlew.bat :app:ktlintCheck               # Kotlin style (ktlintFormat to auto-fix)
./gradlew.bat :app:testDebugUnitTest         # unit tests
./gradlew.bat :app:connectedDebugAndroidTest # instrumented, needs a device

./gradlew.bat :app:assembleDebug
android run --apks=app/build/outputs/apk/debug/app-debug.apk
```

Boot an emulator headlessly:

```bash
emulator -avd <name> -no-window -no-audio -no-snapshot-save -gpu swiftshader_indirect &
adb wait-for-device
adb shell getprop sys.boot_completed    # wait for "1"
```

Keep secrets out of builds. Drive release signing from environment variables so no key material is
committed, and do signed release and Play uploads on a Linux CI runner rather than a developer
machine.

---

## Troubleshooting

Every entry below was hit and diagnosed for real.

### `Could not find or load main class Files\GitHub`

A PATH entry contains a **stray double quote**, e.g. `C:\Program Files\Some Tool"`. Windows builds
many command lines as space-separated strings, so the quote ends the quoting early and the path is
split — Java then treats `Files\Some Tool` as a class name. Gradle unit tests fail for reasons that
look unrelated to PATH.

```powershell
.\scripts\repair-path-quotes.ps1        # report
.\scripts\repair-path-quotes.ps1 -Fix   # repair (elevated for Machine scope)
```

Restart terminals and Gradle daemons afterwards.

### Gradle unit tests crash with "Test process encountered an unexpected problem"

Usually the PATH defect above. Check it before anything else — it fails every Java project on the
machine, not just yours.

### `android emulator` does nothing

Disabled on Windows. Use `emulator` and `avdmanager`.

### Emulator is unusably slow

`emulator -accel-check` is not reporting a usable hypervisor. Enable WHPX (above) and reboot. Do not
fall back to AEHD — it is deprecated and requires Hyper-V off.

### "System UI isn't responding" on a headless emulator

An emulator-side symptom under load, not an app or setup defect. Dismiss it by tapping *Wait* —
`adb shell input tap <x> <y>`, coordinates from `android layout` — or reboot the AVD. Avoid booting
the emulator while a full Gradle build is saturating the CPU.

### `Unable to delete directory` / file-lock errors

A Gradle daemon holds the lock: `./gradlew.bat --stop`, then retry. On Windows, antivirus increases
the odds of this; see the exclusion script.

### `adb devices` shows the wrong thing, or nothing

Keep exactly one adb server. `adb kill-server` then retry. A leftover adb from WSL or another
toolchain competing for port 5037 causes confusing results.

### Builds are slow, or files mysteriously change

Keep projects off OneDrive or any synced folder. Gradle caches, AVD images and file locking interact
badly with sync.

### My plugin stopped working after upgrading to V2

Expected — V1 plugin implementations do not run in V2. Check whether the package depends on
`@opencode/plugin` (V2) or `@opencode-ai/plugin` (V1). If it is V1-only, it needs porting.

### Windows-specific housekeeping

- Use `gradlew.bat`, not `./gradlew`
- `git config --global core.longpaths true`
- Add `.gitattributes`: `gradlew` and `*.sh` must stay LF, `*.bat` CRLF
- Add Defender exclusions for the Gradle cache, SDK and AVD directories

---

## Verifying everything

```powershell
.\scripts\verify-setup.ps1
```

Checks the JDK, `JAVA_HOME`, `ANDROID_HOME`, `adb`, the emulator hypervisor, the platform, the AVD,
the Android CLI, `.androidrc`, Gradle tuning, the OpenCode CLI, global config, skills and agents,
and PATH sanity (stray quotes and duplicates). Exit code is 0 when nothing failed, so it can gate a
first-run checklist. Command resolution uses the persisted Machine + User PATH, so it reports what a
new terminal will actually get rather than what the current process happens to have.

---

## Repository contents

```
README.md                              this guide
LICENSE
scripts/install-toolchain.ps1          provision JDK, SDK, packages, AVD, env vars (no admin)
scripts/verify-setup.ps1               verify every layer; PASS/WARN/FAIL report
scripts/repair-path-quotes.ps1         find/repair PATH entries containing a stray quote
scripts/add-defender-exclusions.ps1    build-speed exclusions (elevated)
docs/session-log.md                    the original machine-specific record, kept as an appendix
```

`docs/session-log.md` is a chronological account of provisioning one specific machine, including
dead ends and open questions. It is the evidence behind this guide, and the place to look when you
want the reasoning rather than the recommendation. It contains machine-specific paths; treat it as
an appendix, not instructions.

## Licence

MIT — see `LICENSE`. Contributions and corrections welcome, particularly for Android Studio
version drift and changes to the Android CLI.
