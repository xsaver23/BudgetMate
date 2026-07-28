# BudgetMate iOS testing

These commands run the native iOS targets without a live Supabase project or
credentials. Run them from the repository root on a Mac with Xcode and an
available iPhone simulator.

## Supported toolchains

The required GitHub Actions lane runs on `macos-15` with Xcode 16.4. The job
fails if that exact Xcode installation is unavailable; it does not fall back to
another Xcode version. This is the compatibility baseline for required CI.

The advisory lane runs the Release build and static analysis with the latest
installed Xcode on `macos-latest`. It is explicitly non-blocking while the
toolchain is being evaluated and records its selected `xcodebuild -version`.
If the advisory runner cannot provide a newer installed Xcode, keep that result
non-blocking and record the limitation in the PR evidence rather than changing
the required lane.

For local parity, inspect the selected toolchain before running the suite:

```sh
xcodebuild -version
swift --version
```

## Inspect the project and resolve packages

```sh
xcodebuild -project BudgetMate.xcodeproj -list -json
ruby generate_project.rb
xcodebuild -project BudgetMate.xcodeproj -list
xcodebuild -project BudgetMate.xcodeproj -scheme BudgetMate -disableAutomaticPackageResolution -resolvePackageDependencies
```

`generate_project.rb` is a read-only integrity validator. It checks the
checked-in targets, configurations, scheme, package lock, bundle identifiers,
assets, and configuration files. It must never delete, recreate, or save
`BudgetMate.xcodeproj`. Its inventory call disables automatic package
resolution, and the package lock must contain the seven identities committed
by the baseline project.

The committed `BudgetMate/Config/Supabase.xcconfig` contains blank safe
defaults. A developer-only `BudgetMate/Config/Supabase.local.xcconfig` may
override those values locally; it is ignored and must never be committed.

## Discover a simulator and build without signing

```sh
SIMULATOR_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')"
test -n "${SIMULATOR_ID}"
DESTINATION="platform=iOS Simulator,id=${SIMULATOR_ID}"
DERIVED_DATA="/tmp/BudgetMate-derived"

xcodebuild \
  -project BudgetMate.xcodeproj \
  -scheme BudgetMate \
  -configuration Debug \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

## Run unit tests

```sh
xcodebuild \
  -project BudgetMate.xcodeproj \
  -scheme BudgetMate \
  -configuration Debug \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test \
  -only-testing:BudgetMateTests
```

The unit target uses fixed UUIDs/dates, an in-memory SwiftData container, and
local cloud-row codecs. It does not make network requests.

## Run UI tests

```sh
xcodebuild \
  -project BudgetMate.xcodeproj \
  -scheme BudgetMate \
  -configuration Debug \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test \
  -only-testing:BudgetMateUITests
```

The smoke test launches with `-ui-testing` and accepts either the first-run
intro or the unauthenticated login screen. It does not require backend setup.

## Run the CI-equivalent local suite

```sh
ruby generate_project.rb
./scripts/verify_ios_secrets.sh
xcodebuild -project BudgetMate.xcodeproj -scheme BudgetMate -disableAutomaticPackageResolution -resolvePackageDependencies

xcodebuild \
  -project BudgetMate.xcodeproj \
  -scheme BudgetMate \
  -configuration Debug \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

xcodebuild \
  -project BudgetMate.xcodeproj \
  -scheme BudgetMate \
  -configuration Debug \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test \
  -only-testing:BudgetMateTests \
  -only-testing:BudgetMateUITests
```

The GitHub Actions workflow runs the same package resolution, unsigned build,
unit tests, UI tests, and secret check on an available iPhone simulator. Test
results and the Xcode result bundle are uploaded as workflow artifacts. The
secret check uses Git's tracked-file scan and Bash regular expressions; it does
not require optional `rg`/ripgrep to be installed.

## Version and build ownership

PR 00A records but does not change the current app version or build number. The
checked-in project and `BudgetMate/Info.plist` do not define explicit
`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `CFBundleShortVersionString`,
or `CFBundleVersion` values. The current release baseline is version `1.0.0`,
build `1`, and remains owned by the existing Xcode-generated defaults until the
explicit release-ownership work in PR 09. Do not add or change version values
as part of the project-integrity or toolchain validation work.
