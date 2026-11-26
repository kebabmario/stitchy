# CI, nightly builds and releases

Stitchy is a Swift package (`Package.swift`: executable target `Stitchy`, test target
`StitchyTests`) with no third-party dependencies. `Scripts/build-app.sh` turns the
binary into `Stitchy.app` (arm64, macOS 14+); `Scripts/make-dmg.sh` packages it.

```
 push / PR to main ──► CI ──────────► tests ─► build Stitchy.app ─► verify signature
                       (macos-26)

 02:00 UTC daily ──► Nightly: check (ubuntu) ── new commit on main? ── no ─► skip
 or manual run                                      │ yes
                                                    ▼
                      build (macos-26): tests ─► build ─► DMG + SHA-256 + build-info.json
                                                    ─► Actions artifact (14 days)

 push tag vX.Y.Z ──► Release: build (macos-26): check tag = Info.plist version ─► tests
                      ─► build ─► DMG ─► [sign + notarize + staple if secrets exist]
                      ─► notes + metadata ──► publish (ubuntu): GitHub Release
```

## Development builds vs stable releases

| | Nightly (development) | Release (stable) |
|---|---|---|
| Source | Latest commit on `main` | A `vX.Y.Z` tag |
| Version | `1.3.0-nightly.20261126+abcdef1` | `1.3.0` |
| Where | Actions artifact, kept 14 days | GitHub Releases page |
| Signing | Always unsigned (ad-hoc) | Unsigned unless Developer ID secrets are set |
| Meant for | Testing what's on `main` | Everyone |

Nightly DMGs are never published as GitHub Releases and never labelled stable. Their
`build-info.json` says `"channel": "development", "stable": false`, and the app's
Info.plist carries `StitchyBuildChannel = development` and `StitchyBuildVersion`.

### Unsigned builds

All builds are **unsigned for distribution**: they carry an ad-hoc signature (needed
to run on Apple silicon), not an Apple Developer ID, and they aren't notarized. macOS
Gatekeeper blocks them the first time. Users open them from
**System Settings › Privacy & Security › Open Anyway**, or with
`xattr -dr com.apple.quarantine /Applications/Stitchy.app`. The DMG includes a short
note explaining this, and release notes say so prominently.

## Building locally

```bash
Scripts/test.sh                 # tests (Command Line Tools or Xcode)
Scripts/build-app.sh            # build/Stitchy.app
Scripts/make-dmg.sh             # build/dist/Stitchy-<version>-arm64.dmg + .sha256
```

`make-dmg.sh` options: `--app <path>` (default `build/Stitchy.app`), `--version <v>`
(default: the app's version), `--out <dir>` (default `build/dist`). It checks the app
bundle and signature, builds a compressed DMG with `hdiutil` containing `Stitchy.app`,
an `Applications` shortcut and (for unsigned builds) an "If Stitchy won't open" note,
mounts it to verify the app is inside and still valid, then writes the SHA-256 file.
Temporary folders are removed on exit.

The code uses the macOS 26 SDK, so builds need Xcode 26 or matching Command Line Tools.

## CI

`.github/workflows/ci.yml` runs on pushes and pull requests to `main` and on demand:
select Xcode 26, resolve the package, run `Scripts/test.sh`, build `Stitchy.app`, and
verify the bundle. Older runs for the same branch or PR are cancelled. The `.build`
cache is keyed on the manifest and only speeds up compilation. The token is read-only,
and pull requests get no secrets.

## Nightly builds

`.github/workflows/nightly.yml` runs at 02:00 UTC.

1. A small Linux job reads the latest commit on `main` and the commits of earlier
   successful nightly runs. If that commit was already built, it stops: no macOS
   minutes are used.
2. Otherwise a macOS job checks out that exact commit, runs the tests, builds an
   unsigned app stamped with the nightly version, packages the DMG, and writes
   `build-info.json` (version, commit, branch, build date, Xcode, workflow run).
3. The artifact **`Stitchy-nightly-<version>`** (version includes the date and short
   commit) holds the DMG, its `.sha256` and `build-info.json`, kept for 14 days.

**Download:** GitHub › Actions › Nightly › pick a run › Artifacts. You need to be
signed in to GitHub to download artifacts.

**Run manually:** Actions › Nightly › **Run workflow**. "Build even if main hasn't
changed" is on by default; turn it off to use the same skip rule as the schedule.

## Releasing

1. Update `CFBundleShortVersionString` (and bump `CFBundleVersion`) in
   `Stitchy/Resources/Info.plist`, update `CHANGELOG.md`, and commit to `main`.
2. Tag that commit and push the tag:

   ```bash
   git tag -a v1.4.0 -m "Stitchy 1.4.0"
   git push origin v1.4.0
   ```

3. `.github/workflows/release.yml` checks the tag matches the Info.plist version
   (otherwise it fails), runs the tests, builds, packages, generates release notes
   from the commits since the previous `vX.Y.Z` tag, and a separate job with write
   permission creates the GitHub Release with the DMG, `.sha256` and
   `build-info.json`. Nothing is published if any step fails, and an existing release
   for the tag is never overwritten.

Tags must be exactly `vMAJOR.MINOR.PATCH` (semantic versioning): `v1.4.0`, `v2.0.0`.

## Enabling Developer ID signing and notarization later

Signing switches on automatically for releases when these repository secrets exist
(Settings › Secrets and variables › Actions). Nightly builds always stay unsigned.

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Your **Developer ID Application** certificate and private key exported as .p12, base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PASSWORD` | The .p12 export password |
| `MACOS_SIGNING_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_APPLE_ID` | Apple ID used for notarization |
| `NOTARY_TEAM_ID` | Your 10-character Team ID |
| `NOTARY_APP_PASSWORD` | An app-specific password for that Apple ID |

With the three certificate secrets, the app is signed with the hardened runtime, a
secure timestamp and `Stitchy/Resources/Stitchy.entitlements` (Apple Events, camera,
microphone, calendars, location), and the signature is verified. With the notary
secrets as well, the DMG is signed, submitted with `notarytool`, stapled with
`stapler`, and checked with `spctl`. The certificate goes into a temporary keychain
that is deleted at the end. Use a Developer ID certificate, not an App Store one.
Signing hasn't been exercised yet, so check the first signed release closely.

Never commit certificates or keys; `.gitignore` excludes `*.p12`, `*.p8`, `*.cer`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "no Xcode 26.x on this runner" | GitHub changed the `macos-26` image. Pick another runner label or set `XCODE_MAJOR` in the workflow. |
| Compile errors only in CI | CI uses the newest Xcode 26 on the runner; check the Xcode version printed by "Select Xcode" against yours. |
| A test fails only in CI | Runners are virtual machines without a logged-in GUI session, camera or hardware video encoder; read the failing test's output and fix the test or the code. Don't disable tests to get green. |
| Release fails at "Validate tag and version" | The tag doesn't match `CFBundleShortVersionString`. Delete the tag (`git push --delete origin vX.Y.Z`), fix Info.plist, re-tag. |
| Release fails at publish | A release for that tag already exists, or the token can't write. Delete the old release if it was a mistake and re-run the job. |
| Nightly skipped | No new commits since the last successful nightly. Run it manually with "Build even if main hasn't changed". |
| Notarization rejected | Run `xcrun notarytool log <submission-id>` with the same credentials to see why (often a missing hardened runtime or an unsigned nested binary). |
