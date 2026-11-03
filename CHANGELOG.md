# Changelog

Dated update history for BudgetMate iOS and web. New published updates use `vYYYY.MM.DD` (with a numeric suffix for additional updates on the same date). These release labels are independent of the iOS bundle and web package versions.

For each future release, add an entry here with user-visible changes, verification, delivery scope, and a source link before publishing its GitHub release.

## v2026.11.02 — 2026-11-02

[Release changes](https://github.com/xsaver23/BudgetMate/pull/29) · [Source commit](https://github.com/xsaver23/BudgetMate/commit/9bc564b27e435b02498be89698fb937e93844a45)

### Fixed

- Locale-aware iOS amount editing, including custom splits and Swiss number formatting.
- Native pacing warnings use actual spending against elapsed budget; projected totals retain full-month budget checks.
- Unchanged category budget edits avoid cloud writes on both platforms; web Enter followed by blur avoids duplicate saves.
- Cloud reads use cursor pagination with completeness validation and retry handling.
- Personal/shared budget selection persists per user, including migration of existing selections.
- Split defaults include active household members, and settlement caches detect split changes.
- Upcoming activity uses calendar-day comparisons and nearest-first ordering.
- Cloud mutation errors remain visible after refresh; sync controls expose status and action to assistive technology.

### Improved

- Consistent projected income, spending, net, and remaining labels; configured budgets retain their own label.
- Web Upcoming panel, future-month explanations, sync feedback, mobile alignment, and contrast.
- Native large-text summary layouts, readable Budget secondary text, and transaction presentation.
- CI selects the newest installed Xcode and newest available iPhone/runtime; release archive and analysis checks remain enabled.

### Delivery and verification

- Web deployed to [budgetmate.pages.dev](https://budgetmate.pages.dev).
- iOS source merged to GitHub; no TestFlight or App Store submission.
- Web: 58 tests and production build passed. Local iOS: 182 unit tests passed, one external-fixture test skipped, and five UI tests passed on iPhone 18 Pro Max / iOS 27.
- Hosted release archive/analysis and server contract checks passed. The first hosted UI attempt failed during simulator accessibility initialization; the retry was still running when the release was verified.
- No production database migration was applied. Concurrent whole-settings edits remain last-write-wins; cursor reads are not atomic snapshots.

## Earlier development history

Backfilled from non-merge Git commits. Dates below are commit dates, not verified deployment or App Store release dates. Original commit titles are retained as the available historical evidence.

### 2026-08-23

- Fix startup and shared budget sync reliability ([5b0bfac](https://github.com/xsaver23/BudgetMate/commit/5b0bfac97e5c50357e87fc4cbd69e1482b43da9d)).

### 2026-08-22

- Fix stale shared budget settings sync ([2a82cf3](https://github.com/xsaver23/BudgetMate/commit/2a82cf37de260eece01247b879f9d484d6f5baf0)).

### 2026-08-09

- Fix settle-up member avatars ([954b7e6](https://github.com/xsaver23/BudgetMate/commit/954b7e68de31685cca844914e9bca5df99d6ba11)).
- Scope member aliases to each budget ([f958a6d](https://github.com/xsaver23/BudgetMate/commit/f958a6dcf054fc40a4584538aa0e9eb38c97e505)).
- Resolve stale transaction member references ([2b8f1ea](https://github.com/xsaver23/BudgetMate/commit/2b8f1eab26e51ccf8a9f2e3f95d88caad24214fc)).
- Bring web app to iOS feature parity ([5f5a17a](https://github.com/xsaver23/BudgetMate/commit/5f5a17a36333386ed8883363e5f426e87bd7ea42)).
- Order daily transactions by newest added ([673b592](https://github.com/xsaver23/BudgetMate/commit/673b5924daf23e0789ada17106f76675091f9509)).

### 2026-08-02

- Finish beta release readiness ([a75e492](https://github.com/xsaver23/BudgetMate/commit/a75e492e9e388e52648a51e6adedff1f68c0a345)).
- test(ios): add synthetic authenticated UI coverage ([e4c2e31](https://github.com/xsaver23/BudgetMate/commit/e4c2e310dd8576accf59e1636fe5c3042200b3af)).
- fix(web): clarify member filters and category budgets ([0c7a094](https://github.com/xsaver23/BudgetMate/commit/0c7a094bc51f5324adefcd64744b4bafd8c009e8)).
- fix(ios): polish phase 2 clarity and layout ([2c1e949](https://github.com/xsaver23/BudgetMate/commit/2c1e949f46a51ef90de40033ca0c23a726f1c874)).
- Repair BudgetMate web responsive layout ([bb4c66f](https://github.com/xsaver23/BudgetMate/commit/bb4c66f9f25fcd9cfd1c9f5339e6a8beaff70894)).
- fix(web): gate household controls by membership ([f12f292](https://github.com/xsaver23/BudgetMate/commit/f12f292c260a464e360b37378917ea5a919b6c5c)).
- fix(ios): scope profile recovery and persistence ([0af42a8](https://github.com/xsaver23/BudgetMate/commit/0af42a87b993dcb24d98b20064227841487f6453)).
- fix: preserve current BudgetMate integration baseline ([e56d1cd](https://github.com/xsaver23/BudgetMate/commit/e56d1cdcb31125dfdc1db4ea378ae9406b2a8fa4)).

### 2026-07-31

- Clarify over-budget amounts ([9af1c41](https://github.com/xsaver23/BudgetMate/commit/9af1c4119463db0a84c7cb4a8f3991cf240faf6e)).
- Fix budget category totals and simplify monthly summary ([0455931](https://github.com/xsaver23/BudgetMate/commit/04559310d067319585dcb123b53dd4a4b1169902)).
- fix(ios): bridge legacy store metadata safely ([7986e73](https://github.com/xsaver23/BudgetMate/commit/7986e735d9ecc9087700776969535fca7a1ceb85)).
- fix(ios): preserve CAD picker symbol in rows ([ceaeeff](https://github.com/xsaver23/BudgetMate/commit/ceaeefffa6000d990bf061f41194a5d9bed419c5)).
- feat(ios): integrate CAD and category UI with Gate C main ([baac186](https://github.com/xsaver23/BudgetMate/commit/baac18665ba09e9b95d0724bb3bb7f68a6064a48)).
- Make Gate C conflicts PostgREST compatible ([f591a7b](https://github.com/xsaver23/BudgetMate/commit/f591a7b40c105d217e6a5d635faf405d6b085309)).

### 2026-07-30

- Bound Gate C mutation lock waits ([8dc4c41](https://github.com/xsaver23/BudgetMate/commit/8dc4c41757520c540d616ef224be9a742a210d6c)).
- Retire legacy Gate C mutation surface ([6fb3127](https://github.com/xsaver23/BudgetMate/commit/6fb312727c358b6e695b3a25a49f1dd6b9161429)).
- Verify Gate C rollback against its snapshot ([c536737](https://github.com/xsaver23/BudgetMate/commit/c5367371bb8ad54a393b0aed0ae78ed21873de4c)).
- Make Gate C safe for the web client ([e0d95da](https://github.com/xsaver23/BudgetMate/commit/e0d95da199f14b5eb6fe1529ba2cec2eb94f5c35)).
- Prepare controlled Gate C rollout ([c9bf939](https://github.com/xsaver23/BudgetMate/commit/c9bf9398093bc2248586bcfc2ac23062a4180fb5)).

### 2026-07-29

- Make trigger migration Supabase CLI compatible (#17) ([0bc1b45](https://github.com/xsaver23/BudgetMate/commit/0bc1b45ab40b4e6d7f9b4a91776fb27f1136ba40)).
- Fix money bridge trigger permissions ([44f59e7](https://github.com/xsaver23/BudgetMate/commit/44f59e7dd39e28a03b7ec9272f17e9167ca7f38d)).
- Harden controlled beta release gate ([1fa7295](https://github.com/xsaver23/BudgetMate/commit/1fa7295f9e4eb1ae63588332615401abb35d31bc)).
- Add shared-data mutation safety gate ([1554f89](https://github.com/xsaver23/BudgetMate/commit/1554f89a470faf7ad1386135b81c2334838428a9)).
- Complete iOS core-use exact money cutover ([476052d](https://github.com/xsaver23/BudgetMate/commit/476052de920597567b3666c033f7b40da49b563e)).
- Accept case-insensitive split UUIDs in money bridge ([6a90948](https://github.com/xsaver23/BudgetMate/commit/6a90948d5a4716559548403c48c26610dbaadc9c)).
- Use PostgreSQL 17 clients in migration CI ([3dc075e](https://github.com/xsaver23/BudgetMate/commit/3dc075eb9b9f0ddfc9eb833955f90d4269300b24)).
- Add server exact-money compatibility bridge ([2ec6f09](https://github.com/xsaver23/BudgetMate/commit/2ec6f09c296626e4bf8f2d2f64268b688aa34239)).

### 2026-07-28

- Add local exact-money compatibility bridge ([442258a](https://github.com/xsaver23/BudgetMate/commit/442258ac8133428552bc3603ad53cc1eb1f395ac)).
- Add exact money domain primitives ([caec59d](https://github.com/xsaver23/BudgetMate/commit/caec59d1bcfbc61c341734549a36c63cbcd0be68)).
- Add data-preserving persistence recovery ([e708a5a](https://github.com/xsaver23/BudgetMate/commit/e708a5ab50d61ea50bd51c8963d6887ecd955129)).
- Add SwiftData V1 compatibility proof ([55b021a](https://github.com/xsaver23/BudgetMate/commit/55b021ab5af3f10cc88a675678954ccd054ff1b5)).
- Guard currency changes after financial history ([f5d31ef](https://github.com/xsaver23/BudgetMate/commit/f5d31ef0afa1c17d0aa54c97f09695fb99eb9a3a)).
- Guard shared record mutations ([cbb999b](https://github.com/xsaver23/BudgetMate/commit/cbb999b94f6d8888ae4636828fbf7023bb3807b7)).

### 2026-07-27

- guard destructive budget actions ([80526f5](https://github.com/xsaver23/BudgetMate/commit/80526f5ef4ccf290f1e7fe93a77cced1e2b8ca70)).
- chore(ios): make project validation non-destructive ([7df3e0b](https://github.com/xsaver23/BudgetMate/commit/7df3e0b5f2506b03bb3b8a917998c5f4d35aaca5)).
- test(ios): add test foundation and CI baseline ([d513d20](https://github.com/xsaver23/BudgetMate/commit/d513d20294eb4f8d3eb7e9161861f7b9821045ac)).

### 2026-07-13

- Harden sync and polish responsive web UI ([e991602](https://github.com/xsaver23/BudgetMate/commit/e9916029d3ff113a0f5d442e6f4be49d46f0ea65)).

### 2026-07-06

- Optimize iOS sync performance ([616c709](https://github.com/xsaver23/BudgetMate/commit/616c7096750479a743699081f3a8341aa0558529)).

### 2026-07-05

- Dedupe web transactions across sync ([0850e9b](https://github.com/xsaver23/BudgetMate/commit/0850e9b417c91f3358a0ce9374edd707d9d0afd3)).
- Prevent transient duplicate transactions ([f338701](https://github.com/xsaver23/BudgetMate/commit/f338701eb3f4da0ef31c51aa70deb71f7774de63)).
- Improve iOS transaction performance ([e961e96](https://github.com/xsaver23/BudgetMate/commit/e961e96548d013716aa0b80de035daf1efcdfcff)).
- Refine transaction rows and monthly budgets ([0cbaec3](https://github.com/xsaver23/BudgetMate/commit/0cbaec3c24861ceb96e55ff964d88bfc1f04346c)).

### 2026-07-04

- Hide unresolved member placeholders ([5710a4c](https://github.com/xsaver23/BudgetMate/commit/5710a4c2f5846565c5e271030604b050a2bf46b6)).
- Canonicalize cloud member identities ([ddf5495](https://github.com/xsaver23/BudgetMate/commit/ddf5495e9926f8eed74f38ef1252dc507d35647d)).
- Resize transaction summary strip ([19d8184](https://github.com/xsaver23/BudgetMate/commit/19d8184f8bac3a6b2c89da24c012e47f0aa652df)).
- Polish transaction summary and avatars ([c0fc5a5](https://github.com/xsaver23/BudgetMate/commit/c0fc5a5a6400c1c8d4d92b257c71c6f3d6e5fb35)).
- Simplify transaction summaries ([e4b916c](https://github.com/xsaver23/BudgetMate/commit/e4b916ce7ae1ef5e1ecd750de8d874390f8a09ff)).
- Improve transaction date group spacing ([75d1c1c](https://github.com/xsaver23/BudgetMate/commit/75d1c1c9ec45d860dd00081845cfb93d764d0255)).
- Add transaction page summaries ([d4acf41](https://github.com/xsaver23/BudgetMate/commit/d4acf41d4441d2acbe14628046921655e78334d1)).

### 2026-07-02

- Improve category pill readability ([2f4f3e7](https://github.com/xsaver23/BudgetMate/commit/2f4f3e7602edba4b5f4f1224f1693fa2b94fc099)).
- Fix transaction member attribution ([eb137ce](https://github.com/xsaver23/BudgetMate/commit/eb137ce9d4933a5f67eed1791b94324bf90a09f9)).

### 2026-06-25

- Remove backup artifacts from public repo ([6078af8](https://github.com/xsaver23/BudgetMate/commit/6078af83d2aac4db1b8960447e515fe070dcffb7)).
- Remove local screenshots from repo ([809bac2](https://github.com/xsaver23/BudgetMate/commit/809bac26d82d79a91fd17af093fdac32925dc9e6)).
- Genericize public sample data ([353b4a7](https://github.com/xsaver23/BudgetMate/commit/353b4a741fa660a5c013590f64d7fc7e26b964d7)).
- Remove local AI tooling from repo ([0f374cb](https://github.com/xsaver23/BudgetMate/commit/0f374cb6a3e6cc86f38e37bdfd6ab915c75cb9c7)).

### 2026-06-22

- Polish GitHub README ([c0e473f](https://github.com/xsaver23/BudgetMate/commit/c0e473ff9fef2a7c085f1ef6556331fe8870213f)).
- Align app styling and transaction ordering ([6752afb](https://github.com/xsaver23/BudgetMate/commit/6752afb5d53468725f8cb091deedba1608e97d10)).
- Improve mobile web layout ([fd4e891](https://github.com/xsaver23/BudgetMate/commit/fd4e89119fb9c93c5d5351a57b6a79a0a2e4657e)).
- Polish desktop web layout ([a84e269](https://github.com/xsaver23/BudgetMate/commit/a84e269e776e4754b7b396eeca5ee5da58985ee3)).
- Use dashboard Pages build settings ([c5feffa](https://github.com/xsaver23/BudgetMate/commit/c5feffa038091cc697b2b0070ca6e5b815a1f74e)).
- Remove Pages redirect fallback ([ec46888](https://github.com/xsaver23/BudgetMate/commit/ec46888bb34c202013bc643a6288b96e5f2cd073)).
- Tighten shared sync and prep web deploy ([994b17c](https://github.com/xsaver23/BudgetMate/commit/994b17c8a52a6f88dabd9d1874ed68481ad10456)).
- Scope web state cache by sync user ([3ab7a2c](https://github.com/xsaver23/BudgetMate/commit/3ab7a2caf74340f0fcca0fc1b7fd24524def0389)).
- Add web companion app and improve sync ([295137a](https://github.com/xsaver23/BudgetMate/commit/295137a9da3f7a66899fdd986b37ada563170e66)).
- Add shared household invite flow and polish settings UI ([26df2c7](https://github.com/xsaver23/BudgetMate/commit/26df2c758a7401e9b398e83bdb9c09880238f43a)).

### 2026-06-21

- Polish settings budget switcher ([cc60007](https://github.com/xsaver23/BudgetMate/commit/cc60007559aaa905152c9c65da4cef69c311b76e)).
- Deduplicate sync upserts and tighten amount entry ([d67d3da](https://github.com/xsaver23/BudgetMate/commit/d67d3da7a04de3848acae1b1281a18fad3836088)).
- Fix shared budget flow regressions ([49d7762](https://github.com/xsaver23/BudgetMate/commit/49d7762a64eabdc896d01fc1ee0b636ac4d8b1ae)).
- Fix crash on duplicate model rows after multi-device sync ([fbd90d7](https://github.com/xsaver23/BudgetMate/commit/fbd90d7331af32c221ae189119425a6b4682dbd3)).
- Speed up launch and scope data queries per budget ([12638d2](https://github.com/xsaver23/BudgetMate/commit/12638d2527e638fd2de4b2f969ba4377b65aa895)).
- Fix Supabase config not reaching app via custom INFOPLIST_KEY ([5c8a8dd](https://github.com/xsaver23/BudgetMate/commit/5c8a8ddeb1dc098920a279471b13a37876ec030e)).
- Refresh BudgetMate UI and sync hardening ([aa8b8ef](https://github.com/xsaver23/BudgetMate/commit/aa8b8ef84df81091f73fe1a320127a51df36e0cd)).

### 2026-06-20

- Polish UI interactions and add app screenshots ([a74b32d](https://github.com/xsaver23/BudgetMate/commit/a74b32d23abe952948e0fdd4e43090a6946a3b86)).
- Apply Impeccable polish pass ([c4e686c](https://github.com/xsaver23/BudgetMate/commit/c4e686c0759a066a949d8260c23ca2044bb1501d)).
- Polish interaction feedback ([9a80317](https://github.com/xsaver23/BudgetMate/commit/9a80317ce251b37f7537e906051b9b9058d7aaac)).
- Add UI design skills ([b7d0370](https://github.com/xsaver23/BudgetMate/commit/b7d0370d6ff5f729254d9bb88e6bda1389d8659d)).
- Add Impeccable design context and polish UI ([79bc116](https://github.com/xsaver23/BudgetMate/commit/79bc116a8de1ba59306dbfd2969125a8a3f6ad9d)).

### 2026-06-18

- Improve sync status and add app icon ([5653bb7](https://github.com/xsaver23/BudgetMate/commit/5653bb70a8e290e3bad7674fd7254b651cc33e33)).
- Seed cloud with local-only shared transactions ([4343263](https://github.com/xsaver23/BudgetMate/commit/4343263ff5e2c123e3f69a5f4e875b3d3a6fed87)).
- Allow shared-budget members to bulk sync rows ([59c6fb5](https://github.com/xsaver23/BudgetMate/commit/59c6fb529e89ddd0b085294238fa489faf6da116)).
- Self-heal legacy shared member profiles on sync ([e1b2bf8](https://github.com/xsaver23/BudgetMate/commit/e1b2bf89038393c2e0be315e35f08e75056255dc)).
- Backfill legacy shared member auth links ([b98be13](https://github.com/xsaver23/BudgetMate/commit/b98be132a6a1c27c96bcbfc93fbddb0002b472a2)).
- Match legacy members by email during sync ([d0a74d5](https://github.com/xsaver23/BudgetMate/commit/d0a74d58e5d5661c3bcb1331122a715b3bacf265)).
- Avoid bulk syncing other members records ([04967b3](https://github.com/xsaver23/BudgetMate/commit/04967b3069393c631ce934e2c7771b8aa1062690)).
- Harden shared budget membership access ([4d67631](https://github.com/xsaver23/BudgetMate/commit/4d6763184e9eba848815472a3cf2c64d597d4c06)).
- Sanitize transaction amount input ([0c754ff](https://github.com/xsaver23/BudgetMate/commit/0c754ff1e79a42470b98dbab286631f63c7b1f8b)).
- Restore profile completion from cloud ([eba409c](https://github.com/xsaver23/BudgetMate/commit/eba409c954d70b7a68cc4a3ff7280f954998ec3e)).
- Prefer signed in member after sync ([f681050](https://github.com/xsaver23/BudgetMate/commit/f68105023840e9062f7dd6d6af8406ad465a06e0)).
- Fix app bundle identifier ([91f1e9d](https://github.com/xsaver23/BudgetMate/commit/91f1e9de69d4b9d1bb35d2d4e08b177d605c1ea8)).
- Improve shared budget auto sync ([b8dd8bb](https://github.com/xsaver23/BudgetMate/commit/b8dd8bb53b49c0f68679d83274f9b65d4098dfba)).
- Show all settlement balances ([7c4ca0c](https://github.com/xsaver23/BudgetMate/commit/7c4ca0c68d5747ec1fe2e909714369abb6d4c4de)).
- Polish budget tab styling ([ae160bb](https://github.com/xsaver23/BudgetMate/commit/ae160bb1b245c8985d789295f2251250e2166b9a)).
- Initial commit ([6b186d2](https://github.com/xsaver23/BudgetMate/commit/6b186d243742584b6b4c3233448c74c3dbf87075)).
- Initial BudgetMate app commit ([16e5b3f](https://github.com/xsaver23/BudgetMate/commit/16e5b3fbd2dea31edd4a08db8fa8c93aed56f208)).

