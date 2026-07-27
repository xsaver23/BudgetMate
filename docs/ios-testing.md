# BudgetMate iOS testing

These commands run the native iOS targets without a live Supabase project or
credentials. Run them from the repository root on a Mac with Xcode and an
available iPhone simulator.

## Inspect targets and resolve packages

```sh
xcodebuild -project BudgetMate.xcodeproj -list
xcodebuild -project BudgetMate.xcodeproj -scheme BudgetMate -resolvePackageDependencies
```

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
./scripts/verify_ios_secrets.sh
xcodebuild -project BudgetMate.xcodeproj -scheme BudgetMate -resolvePackageDependencies

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
results and the Xcode result bundle are uploaded as workflow artifacts.
