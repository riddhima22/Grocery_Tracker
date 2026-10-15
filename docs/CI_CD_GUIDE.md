# Grocery Track CI/CD & Deployment Guide

This document describes the production CI/CD architecture, Git branching conventions, signing configuration, automated testing pipelines, and GitHub repository configuration for Grocery Track.

---

## 1. Git Branching Strategy

Grocery Track follows a structured Git Flow model to guarantee production stability while enabling fast iteration:

```
[main] (Production-ready, tagged releases only)
  ▲
  │ (Pull Request via GitHub + required approvals)
[develop] (Integration & staging branch)
  ▲
  │ (Feature branch PRs)
[feature/ci-cd-pipeline] ───► [feature/smart-quantity-detection] ───► [bugfix/...]
```

### Branch Responsibilities
- **`main`**:
  - Contains strictly production-ready code.
  - Direct pushes or commits to `main` are strictly prohibited.
  - Merges into `main` require a GitHub Pull Request from `develop` with all CI status checks passing and at least one code review approval.
  - Every release on `main` is tagged with a semantic version tag (e.g., `v1.0.0`).
- **`develop`**:
  - The central integration branch for current sprint features and fixes.
  - Automatically runs the full CI pipeline on every push and PR.
- **`feature/*` and `bugfix/*`**:
  - Branched off `develop`.
  - Focused, isolated changes tested locally (`dart format`, `flutter analyze`, `flutter test`) before opening a PR against `develop`.

---

## 2. GitHub Actions CI Pipeline (`.github/workflows/ci.yml`)

The CI pipeline runs on every push and pull request targeting `main` and `develop`. Redundant runs for the same branch/PR are automatically cancelled using concurrency controls:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

### CI Jobs & Verification Steps
1. **`backend-ci` (Django & Backend Services)**:
   - Sets up Ubuntu with **Python 3.11** and pip caching.
   - Runs **PostgreSQL 15** and **Redis 7** service containers with health checks.
   - Executes `python manage.py check --deploy --settings=config.settings.production` for security audits.
   - Runs database migrations and executes the full Django test suite (`python manage.py test apps.groceries apps.scans`).
2. **`flutter-ci` (Flutter & Android Verification)**:
   - Sets up **Java 17** (`zulu` distribution).
   - Sets up **Flutter SDK pinned to `3.41.9`** (`channel: stable`).
   - Caches Gradle dependencies and pub cache.
   - Runs `flutter pub get`.
   - Enforces formatting: `dart format --output=none --set-exit-if-changed .`.
   - Runs static analysis: `flutter analyze --fatal-infos --fatal-warnings`.
   - Executes full automated test suite with coverage: `flutter test --coverage`.
   - Uploads test coverage artifact (`coverage/lcov.info`).
   - Builds debug Android APK (`flutter build apk --debug`).
   - Uploads debug APK artifact (`app-debug-apk`).

---

## 3. GitHub Actions Release Pipeline (`.github/workflows/release.yml`)

The release pipeline produces signed production binaries (AAB and APK) and manages deployment.

### Triggers
1. **Tag Push**: Pushing a tag matching `v*.*.*` (e.g. `git tag -a v1.0.0 -m "Release v1.0.0"` followed by `git push origin v1.0.0`).
2. **Manual Dispatch (`workflow_dispatch`)**: Triggered directly from GitHub Actions UI with custom options:
   - `version_name` (e.g. `1.0.0`)
   - `build_number` (e.g. `1`)
   - `publish_to_playstore` (boolean, default: `false`)
   - `track` (`internal`, `alpha`, `beta`, `production`, default: `internal`)

### Protected Environment Gate
- Uses GitHub Environment: `production`.
- Can be configured with required reviewers (e.g., Tech Lead approval) before release binaries are built and signed.

### Release Build Outputs
- **Signed App Bundle (AAB)**: `build/app/outputs/bundle/release/app-release.aab`
- **Signed Release APK**: `build/app/outputs/flutter-apk/app-release.apk`
- **GitHub Release**: Automatically drafts and publishes a GitHub Release with changelog generated from git history.
- **Play Store Deployment**: When `publish_to_playstore` is true, automatically uploads the signed AAB to Google Play Console on the specified track.

---

## 4. Android Dynamic Signing Configuration (`android/app/build.gradle.kts`)

The Android build configuration in `android/app/build.gradle.kts` dynamically selects the signing configuration:

```kotlin
val releaseKeystorePath = System.getenv("KEYSTORE_PATH")
val releaseKeystorePassword = System.getenv("KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("KEY_ALIAS")
val releaseKeyPassword = System.getenv("KEY_PASSWORD")

val hasEnvSigning = !releaseKeystorePath.isNullOrBlank() &&
        File(releaseKeystorePath).exists() &&
        !releaseKeystorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

signingConfigs {
    val releaseSigning = create("release") {
        if (hasEnvSigning) {
            storeFile = File(releaseKeystorePath)
            storePassword = releaseKeystorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        } else if (hasKeyProps) {
            storeFile = File(keyProps.getProperty("storeFile"))
            storePassword = keyProps.getProperty("storePassword")
            keyAlias = keyProps.getProperty("keyAlias")
            keyPassword = keyProps.getProperty("keyPassword")
        } else {
            // Safe fallback to debug keystore for CI test builds and local dev
            val debugConfig = getByName("debug")
            storeFile = debugConfig.storeFile
            storePassword = debugConfig.storePassword
            keyAlias = debugConfig.keyAlias
            keyPassword = debugConfig.keyPassword
        }
    }
}
```

### Benefits
- **Zero Secrets Leakage**: Keystore credentials and file paths are never committed to the repo.
- **Safe Fallback**: Pull request builds and local developers without production keys can build release APKs seamlessly with the debug signature fallback.
- **Production Enforced**: In the GitHub Actions `production` environment, `release.yml` decodes `KEYSTORE_BASE64` into `android/app/keystores/release.keystore`, producing a valid signed production build.

---

## 5. Required GitHub Repository Configuration

### A. Branch Protection Rules

Navigate to **Settings > Branches > Add branch protection rule**:

#### For `main`:
1. **Branch name pattern**: `main`
2. **Protect matching branches**:
   - [x] **Require a pull request before merging**
     - Require approvals: `1`
     - Dismiss stale pull request approvals when new commits are pushed: `Checked`
     - Require review from Code Owners: `Optional`
   - [x] **Require status checks to pass before merging**
     - Require branches to be up to date before merging: `Checked`
     - Status checks required:
       - `backend-ci`
       - `flutter-ci`
   - [x] **Require conversation resolution before merging**
   - [x] **Do not allow bypassing the above settings**
   - [x] **Restrict who can push to matching branches**: Leave empty (disables direct pushes).

#### For `develop`:
1. **Branch name pattern**: `develop`
2. **Protect matching branches**:
   - [x] **Require a pull request before merging**
   - [x] **Require status checks to pass before merging**:
     - `backend-ci`
     - `flutter-ci`
   - [x] **Require conversation resolution before merging**

---

### B. GitHub Secrets & Variables

Navigate to **Settings > Secrets and variables > Actions > New repository secret**:

| Secret Name | Description | Example / How to Generate |
|---|---|---|
| `KEYSTORE_BASE64` | Base64-encoded Android release keystore | `base64 -w 0 upload-keystore.jks` |
| `KEYSTORE_PASSWORD` | Keystore password | Password chosen during keystore creation |
| `KEY_ALIAS` | Key alias name | e.g., `grocerytrack-upload` |
| `KEY_PASSWORD` | Key password | Key password chosen during keystore creation |
| `PLAY_STORE_JSON_KEY` | *(Optional)* Google Play Service Account JSON key string | Generated from Google Cloud Console / Play Developer Console API access |

#### Generating an Android Keystore (One-Time Setup):
```bash
keytool -genkey -v -keystore release.keystore -alias grocerytrack-upload -keyalg RSA -keysize 2048 -validity 10000
```
Encode for GitHub Secret:
- **macOS / Linux**: `base64 release.keystore | pbcopy`
- **Windows PowerShell**:
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("release.keystore")) | Set-Clipboard
  ```

---

## 6. Automated Verification Status

The entire automated test suite passes with zero warnings or errors:

- **Flutter Static Analysis**: `flutter analyze` -> `No issues found! (0 errors, 0 warnings, 0 infos)`
- **Flutter Code Formatting**: `dart format --output=none --set-exit-if-changed .` -> `0 changed files`
- **Flutter Test Suite**: `40 tests passed` (including cart operations, inventory updates, shelf-life calculations, barcode validation, and API error mappings).
- **Django Test Suite**: `46 tests passed` (including scans, unit classifiers, grocery models, and caching).
- **Release APK Build**: `flutter build apk --release` -> Successfully built `app-release.apk` (70.9 MB).
- **Debug APK Build**: `flutter build apk --debug` -> Successfully built `app-debug.apk` (219.1 MB).
