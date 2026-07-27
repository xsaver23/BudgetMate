# iOS performance baseline procedure

PR 0 records the measurement procedure and the existing signpost names. It
does not claim timing numbers that have not been measured. Capture results on
the same Mac, Xcode version, simulator model, build configuration, and data
fixture so later hardening phases can compare like with like.

## Prepare a repeatable run

Use the command sequence in [iOS testing](ios-testing.md) to resolve packages,
select a simulator, and build an unsigned Debug app. For each scenario, record
at least five warm runs plus one separately labelled cold run. Do not use a
real cloud account for fixture data.

To observe the app’s structured logs from a booted simulator, run:

```sh
xcrun simctl spawn "${SIMULATOR_ID}" log stream \
  --style compact \
  --level debug \
  --predicate 'subsystem == "BudgetMate"'
```

Use Instruments’ **Points of Interest** and **Time Profiler** templates while
repeating the same action. The signpost names below are the source of truth;
do not infer a duration from a log message that is only an event.

## Existing launch and interaction instrumentation

| Measurement | Subsystem/category | Existing signpost or log | Start/finish rule |
| --- | --- | --- | --- |
| Cold launch | `BudgetMate/Launch` | `ModelContainer Open` interval | Start when the model container opens; end when the interval closes. Reset simulator app data between cold runs. |
| Cached-session launch | `BudgetMate/Launch` | `Cached Auth Session Read Finished` event and matching duration log | Measure from the launch action to the event; keep the cached session state constant across warm runs. |
| Local UI ready | `BudgetMate/Launch` | `Local UI Ready` event | Measure from launch to the first local authenticated UI reveal. Use a prepared local session only; do not wait for cloud sync. |
| Add-transaction presentation | `BudgetMate/Interaction` | `Add Transaction Requested`, then `Transaction Editor Appeared` | Measure the interval between the button event and editor event. |
| First keyboard presentation | `BudgetMate/Interaction` | `First Keyboard Will Show` event and matching duration log | Measure from editor appearance to the first keyboard event. Keep the same focused field and keyboard type. |
| Dashboard metrics | `BudgetMate/DashboardMetrics` | `Refresh Metrics` interval | Measure the interval around one derived-metrics refresh after the dashboard is visible. |

The cached-session and local-UI events are points, not paired intervals. Use
their adjacent launch log timestamps for elapsed time, or instrument the run in
Instruments with the event marker. Do not report a duration for a point unless
the start boundary is explicitly recorded.

## Data-volume scenarios

Run dashboard metrics with deterministic local fixtures containing exactly
1,000 and 10,000 transactions. Keep the same mix of income, regular expense,
split expense, and recurring rows for both volumes, and keep members and the
selected month fixed. Seed the simulator only through a local development/test
harness; PR 0 deliberately adds no production data-seeding path.

For each volume, capture:

1. time to local UI ready after the fixture is available;
2. one `DashboardMetrics/Refresh Metrics` interval with no member filter;
3. one interval with the member filter enabled; and
4. memory and main-thread samples from Time Profiler.

Repeat the same matrix with the dashboard’s month selection unchanged. Report
the raw runs, median, and slowest run in the follow-up phase rather than adding
numbers to this procedure without evidence.

## Full-sync scenarios

Use a local Supabase test project or a deterministic service mock that returns
exactly 1,000 and 10,000 transaction rows in one budget scope. Never point the
benchmark at production. Keep settings, members, settlement rows, and network
conditions fixed between the two volumes.

The current implementation exposes the `BudgetMate/CloudSync` logger for sync
errors and status diagnostics, but it does not currently emit a paired full-sync
OSSignposter interval. Measure the full-sync action with Instruments’ Time
Profiler/network instruments and record the request count, wall-clock duration,
main-actor time, and SwiftData save count. A future sync-hardening phase may add
a dedicated interval after the measurement boundary is agreed; PR 0 does not
change sync behavior solely to manufacture a baseline.

For each of 1,000 and 10,000 rows, capture:

- pull and merge wall-clock time;
- push time when the fixture is dirty;
- idle re-sync time after the first merge;
- number of changed SwiftData rows and saves; and
- peak memory and main-thread occupancy.

Keep the fixture and captured logs with the benchmark report so later phases can
reproduce the result.
