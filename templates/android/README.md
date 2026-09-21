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

## Verify after applying

```bash
./gradlew.bat :app:compileDebugKotlin
./gradlew.bat :app:lintDebug
./gradlew.bat :app:ktlintCheck        # ./gradlew.bat ktlintFormat to auto-fix
./gradlew.bat :app:testDebugUnitTest
```

If `ktlintCheck` reports a `standard:filename` or function-naming violation you did not expect,
check that `.editorconfig` landed at the project root — ktlint will not read it from anywhere else.
