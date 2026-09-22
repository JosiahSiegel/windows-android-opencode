# Owner-sideload QA release

How to give an owner an installable APK for their own phone, from a Windows machine, without
confusing it with a store release. Derived from doing this for real, including one disaster: the
release key was lost with a retired container.

**A branch push is not a release.** A branch push is reversible plumbing; a GitHub release is a
*publish*. Never conflate them in a report or a promise.

## What it is / is not

| It is | It is not |
|---|---|
| A private, owner-installable QA APK signed with an owner-local key | A Google Play or production release |
| Built by a dedicated `sideload` build type (`isDebuggable = false`) | The `release` build type, or a debug build |
| Attached to a private GitHub release tagged `vX.Y.Z-sideload` | A public distribution |
| For the owner's own device testing | Evidence of market or revenue validation |

Keep a debug build as an explicit **fallback** only (see below). It is a different artifact and must
be labelled as such.

## Preconditions (fail closed - abort if any is false)

- **Explicit owner authorization** for *this* release; record the request verbatim. A release is a
  publish and needs the owner's word.
- **Signing material present and git-ignored**: a signing properties file at the repo root and the
  keystore it points at. If the build reports the file is missing, stop and ask the owner — never
  invent a key and never fall back to the debug key (the signer DN must be the owner key; using the
  debug key produces an artifact that cannot update an existing install and misrepresents the build).
- **Tools**: `apksigner` and `apkanalyzer`. On Windows `apksigner.bat` ships in
  `%ANDROID_HOME%\build-tools\<latest>\` but **`apkanalyzer.bat` ships in
  `%ANDROID_HOME%\cmdline-tools\latest\bin\`** — it is not in `build-tools`, which trips people up.
- **`gh` authenticated** as the owner and the repository **private** (`gh repo view --json isPrivate`).
- The branch being released is not behind its upstream.

## Naming

| Item | Convention |
|---|---|
| Git tag | `v<MAJOR>.<MINOR>.<PATCH>-sideload` |
| Release title | `<App> <version> - owner sideload (<short description>)` |
| Asset name | always the same file name, so install instructions do not change |
| `versionCode` / `versionName` | bumped and **committed** before tagging; the tag must contain the version it reports |
| Release target | the feature branch the APK was built from |

## Steps

1. **Version + records.** Bump `versionCode`/`versionName` and update whatever release-record JSON
   your project keeps. Commit it. (The tag must point at a commit that contains the version it
   advertises.)
2. **Build** the dedicated sideload variant, through the build lock
   (`gradle-lock.ps1`) so a concurrent build cannot corrupt it. No emulator running during a heavy
   Gradle build.
3. **Verify the artifact - do not skip:**
   ```bash
   BT=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)
   CT="$ANDROID_HOME/cmdline-tools/latest/bin"     # apkanalyzer lives here, not in build-tools
   APK=app/build/outputs/apk/sideload/app-sideload.apk
   "$BT/apksigner" verify "$APK"                    # must exit 0
   "$BT/apksigner" verify --print-certs "$APK"      # DN must be the owner key, NOT "Android Debug"
   "$CT/apkanalyzer" manifest version-code "$APK"
   "$CT/apkanalyzer" manifest version-name "$APK"
   "$CT/apkanalyzer" manifest debuggable "$APK"     # must be false
   ```
   If the signer DN is `CN=Android Debug`, you built the wrong variant - stop.
4. **Smoke-test it** on an emulator before the owner installs it, so they do not hit a crash:
   install, launch, and read the crash buffer (`adb logcat -b crash` must be empty).
   In a **remote desktop** session the emulator's window path crash-loops; run it headless
   (`-no-window -gpu swiftshader_indirect`) for this. See `docs/environment-gaps.md`.
5. **Commit, tag, push:**
   ```bash
   git commit -m "release: prepare owner-sideload vX.Y.Z (versionCode N)"
   git tag -a vX.Y.Z-sideload -m "Owner sideload vX.Y.Z - <what>"
   git push origin <feature-branch>
   git push origin vX.Y.Z-sideload
   ```
6. **Create the private release** (not draft, not prerelease, targeting the same branch you built):
   ```bash
   gh release create vX.Y.Z-sideload app/build/outputs/apk/sideload/app-sideload.apk \
     --title "<App> X.Y.Z - owner sideload (<what>)" \
     --notes-file <notes.md> --target <feature-branch>
   ```
7. **Round-trip the asset.** Download it again and compare hashes with the built file; confirm
   `isDraft=false`, `isPrerelease=false`, `targetCommitish` is your branch, and the repo is still
   private. A local-only hash proves nothing about what was uploaded.
8. **Record the run**: authorization reference, commit, tag, asset name/size/sha256, signer DN,
   `isDebuggable`, smoke-test result, the downloaded-hash match, and the "not claimed" boundaries.

## Release notes must state

- "Private owner sideload artifact - NOT a Google Play or production release."
- versionCode / versionName, package, and that the `applicationId` is still the working placeholder.
- Signing: owner-key DN, `isDebuggable = false`.
- APK sha256 and size, and the build command.
- What changed since the previous sideload.
- The authorization reference.
- Install steps, including whether the previous build must be uninstalled first.
- "Not claimed": not Play/production; which QA states were **not** evaluated.

## Re-keying (the release key was lost)

If the key is gone - for example it only ever lived in a container that has since been retired -
it cannot be recovered. **The owner must create the new key**; the agent must not handle signing
material. Consequences to state plainly:

- The new APK is signed by a different key, so Android refuses to update an existing install in
  place. The owner must **uninstall** the previous build first.
- Every future sideload must use this same key, so **back up the keystore and its password** before
  the first release that uses it. Losing it again means another re-key and another forced uninstall.
- The re-key is an owner decision; record it in the release notes and the run record.

Owner-run, once (Windows), choosing their own password:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.android-keystores" | Out-Null
& "$env:JAVA_HOME\bin\keytool.exe" -genkeypair -v `
  -keystore "$env:USERPROFILE\.android-keystores\<app>-release.jks" `
  -storetype PKCS12 -keyalg RSA -keysize 4096 -validity 10950 `
  -alias <app> `
  -dname "CN=<App> Local Release, OU=Local Build, O=Local Development, C=US"
```

Then set the signing properties at the repo root (git-ignored) to an **absolute** path:

```properties
storeFile=C:\\Users\\<you>\\.android-keystores\\<app>-release.jks
storePassword=<the password you chose>
keyAlias=<app>
keyPassword=<the same password; PKCS12 uses one>
```

### Pitfall: a relative `storeFile` resolves against the module, not the root

`storeFile = file(...)` inside `app/build.gradle.kts` resolves a relative path against the **`app`
module directory**, so a value like `home/vscode/.android-keystores/key.jks` becomes
`<repo>/app/home/vscode/...` and never matches. Use an absolute path.

## Fallback: a labelled debug QA build (no key required)

If the owner needs to test and no release key is available (lost, or they cannot create one), ship
the **debug** APK instead - but only with the owner's explicit agreement, and label it in every
place that matters:

- Tag it differently (`vX.Y.Z-debug`), never `-sideload`.
- Title and notes say **DEBUG QA build - not the sideload release**; state `debuggable=true` and that
  the signer is `CN=Android Debug`.
- Say that the previous install must be uninstalled (different signer).
- Still run steps 3-4, 6-8 (verify, smoke-test, private release, round-trip, record).

A debug build is acceptable for "let me look at this on my phone". It is not a substitute for the
signed artifact, and the release record should say the sideload release is still pending.
