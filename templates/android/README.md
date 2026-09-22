# Android post-scaffold additions

Snippets to apply **on top of** a freshly scaffolded Android project — not a project to copy.

Scaffold first, so you inherit Google's current SDK, AGP, Kotlin and Compose defaults:

```bash
android create --name="My App" --output=<dir> empty-activity
```

Then apply the files below. Nothing here pins a library version except ktlint, so nothing goes stale
when Google's template advances. That is the whole point of not shipping a frozen project to copy.

| File | Destination | Action |
|---|---|---|
| `.editorconfig` | project root | copy as-is |
| `.gitattributes` | project root | copy as-is |
| `ci-android.yml` | `.github/workflows/android.yml` | copy as-is |
| `gradle-libs.versions.toml.snippet` | `gradle/libs.versions.toml` | add both entries |
| `root-build.gradle.kts.snippet` | `build.gradle.kts` | add one plugin line |
| `app-build.gradle.kts.snippet` | `app/build.gradle.kts` | add plugin alias, then three blocks |
| `AGENTS.md.snippet` | project `AGENTS.md` | copy the sections that apply (env, build lock, emulator, goldens, release) |

## Why each one exists

**`.editorconfig` — ktlint versus Compose.** ktlint's `function-naming` rule demands camelCase;
Jetpack Compose uses PascalCase for `@Composable` functions. Without the exemption, every Compose
project fails lint on its first screen. The exemption is scoped to `@Composable` only, so ordinary
functions are still checked. The `filename` rule is disabled because it fires on any file holding a
single top-level declaration, which is a normal and intentional Kotlin pattern.

**`app-build.gradle.kts.snippet` — environment-driven signing.** Release signing reads its keystore
path, store password, key alias and key password from environment variables. If
`ANDROID_KEYSTORE_PATH` is unset, no signing config is created at all and debug builds are entirely
unaffected. This is what makes "never commit key material" enforceable rather than aspirational, and
it is the single fiddliest piece here to get right.

**`ci-android.yml` — sign on CI, not on a laptop.** Verify runs on every push: compile, lint, ktlint
and unit tests. The release job is manual-only and runs on Linux, so the keystore and Play service
account never touch a developer machine. Adapt the release job to your publishing mechanism: Gradle
Play Publisher is the natural choice on a Gradle project.

**`.gitattributes`** — keeps `gradlew` and `*.sh` at LF and `*.bat` at CRLF. Mixing these up is a
classic Windows-only breakage that passes locally and fails in CI.

## Cross-platform portability (Windows)

A project that builds on Linux CI but is developed on Windows is a common trap: Gradle is portable,
hand-written tooling usually is not. A verification script must actually have run on the target OS
before that profile can be called VERIFIED there. Defects found the hard way in a real project:

- `./gradlew` is not an executable name on Windows - use `gradlew.bat`;
- a JDK contains `java.exe`, not `java`, so an `is_file()` check for `bin/java` is always false;
- Windows `CreateProcess` cannot launch a `.cmd` shim by bare name - use `sys.executable` for Python
  sub-steps (and make sure `python3` itself is shell-agnostic, see `docs/environment-gaps.md`);
- `select(2)` cannot observe a subprocess pipe (`WinError 10093`) - drain output on a reader thread;
- `os.killpg` / `start_new_session` are POSIX-only - use `taskkill /T` on Windows;
- SDK tools are `adb.exe`, not `adb`.

Each of these silently makes a real gate **unrunnable**, and an unrunnable check is easy to mistake
for "nothing to do". Treat "the check could not run" as a finding, never as a pass - that is what
`docs/environment-gaps.md` exists for.

## Screenshot goldens are OS-bound

JVM screenshot tests (Roborazzi) render through the host's font stack, so goldens recorded on one OS
do not match another even for byte-identical source. A common trap is to see 20+ "changed" goldens
on a fresh checkout and re-record them all.

- **A project has exactly one canonical host, recorded in the repo** - for example
  `app/src/test/screenshots/recording-host.txt` holding `windows` or `linux`. The verification entry
  point reads it and reports **NOT EVALUATED** on any other OS, so a cross-host diff never masquerades
  as a failure and never tempts a wholesale refresh.
- **Do not re-record to clear a diff on a different OS.** Verify first that the diff is the intended
  UI change; if untouched screens also differ, it is the host, not the code.
- **Moving the canonical host is a deliberate decision, not a snapshot refresh.** When the development
  environment changes (for example retiring a Linux devcontainer in favour of Windows), re-record the
  whole set *on the new host* once, flip the marker in the same commit, and say so - that is a
  re-baseline. Doing it silently to get a green run is the thing to avoid.
- A UI change legitimately makes *its* goldens stale - re-record those, on the canonical host, as part
  of that change.
- Where the golden profile cannot run (a different OS), report **NOT EVALUATED**.

A compact gate for a Python verification entry point (`recording-host.txt` holds `windows` or
`linux`):

```python
def current_host_family() -> str:
    if os.name == "nt": return "windows"
    if sys.platform == "darwin": return "darwin"
    return "linux"

marker = ROOT / "app/src/test/screenshots/recording-host.txt"
recorded_on = marker.read_text(encoding="utf-8").strip().lower() if marker.is_file() else None
if recorded_on and recorded_on != current_host_family():
    sys.stderr.write(
        f"e2e: NOT EVALUATED on {current_host_family()}: goldens were recorded on {recorded_on}; "
        "JVM screenshot rendering is host-dependent, so the comparison is not run and is NOT a pass.\n"
        f"e2e: unblock: run this in the canonical environment ({recorded_on}).\n")
    return 1
```

Exit non-zero: `NOT EVALUATED` is not a pass, and a zero exit would let it be read as one.

## Before you trust the project's own tooling

The Gradle build is portable; hand-written Python, shell and Node tooling usually is not, and an
unrunnable check is easy to mistake for "nothing to do". Run the checker from the setup repo:

```powershell
./scripts/check-script-portability.ps1 -Path D:\repos\my-app
```

It flags the specific defects found in the field (`./gradlew`, bare `python3` in a subprocess,
`select()` on a pipe, `os.killpg`, `bin/java`, `platform-tools/adb`, PATHEXT) with the fix, and
reports platform-aware files as INFO so a human confirms rather than the lint guessing. Exit code is
non-zero when a blocking defect exists, so it can gate a build.

## Releasing an APK for the owner's phone

Do not improvise this. The end-to-end process - build the signed sideload variant, verify the signer
(not the debug key), smoke-test headless, tag, publish a **private** release, round-trip the hash -
is in `docs/owner-sideload-release.md`, including the re-key procedure if the release key is ever
lost and the fallback when no key exists at all.

## Verify after applying

```bash
./gradlew.bat :app:compileDebugKotlin
./gradlew.bat :app:lintDebug
./gradlew.bat :app:ktlintCheck        # ./gradlew.bat ktlintFormat to auto-fix
./gradlew.bat :app:testDebugUnitTest
```

If `ktlintCheck` reports a `standard:filename` or function-naming violation you did not expect,
check that `.editorconfig` landed at the project root — ktlint will not read it from anywhere else.
