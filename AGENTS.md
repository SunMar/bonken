# AGENTS.md

Bonken — offline score calculator for the Dutch 4-player card game Bonken.
Primarily a native Flutter app for Android + iOS/iPadOS, with a web PWA build
too (used mainly for testing). Pure Dart domain → Riverpod state → Material 3 UI.

**Full architecture & rationale: [ARCHITECTURE.md](ARCHITECTURE.md).** Player-facing docs
(Dutch): [README.md](README.md).

## Commands

```bash
fvm flutter pub get
fvm flutter test                                   # full suite
fvm flutter analyze --fatal-infos                  # static analysis (CI fails on infos)
fvm dart format .                                  # auto-format (run before committing)
fvm dart format --output=none --set-exit-if-changed .  # formatting check (CI gate)
```

Flutter is pinned in `.fvmrc`; CI installs from there. Always use `fvm flutter`/`fvm dart`
to run against the pinned version.

## Before you finish

CI's [`verify`](.github/actions/verify/action.yml) action enforces three gates
**in order** — `dart format --set-exit-if-changed` → `flutter analyze
--fatal-infos` → `flutter test` — plus `dart fix --dry-run` (fails on any
proposed fix). Run them locally; analyze + test alone miss formatting drift.
Before pushing: `fvm dart fix --apply` + `fvm dart format .`. The analyzer is
strict by design — write explicit types/return types and wrap fire-and-forget
futures in `unawaited(...)`; full rule set + rationale in
[`analysis_options.yaml`](analysis_options.yaml) / [ARCHITECTURE.md §12](ARCHITECTURE.md).

**Always check `AGENTS.md` and `ARCHITECTURE.md` on every task** — if the change
affects anything documented here, update it inline. Do not defer to a follow-up.

**Add or update tests to cover every changed behaviour.** Check existing coverage
for the area you touched and fill gaps — [ARCHITECTURE.md §11](ARCHITECTURE.md)
for testing conventions (timer stubs, provider overrides, fixture helpers).

## Conventions (do not break)

- **Key per-round data by player UUID**, never seat index — derive indices on demand — [ARCHITECTURE.md §2](ARCHITECTURE.md).
- **Screens use `AppScaffold`**; icons are `Symbols.*` only (never `Icons`). The model layer stays pure (no Flutter UI / up-imports) and state/services never import `lib/{screens,widgets,theme,navigation}`. All of these — plus the bottom-sheet/snackbar wrappers below — are source-scanned by `test/architecture_test.dart` — [ARCHITECTURE.md §2](ARCHITECTURE.md).
- **Imperative navigation goes through `AppRoutes`** (`lib/navigation/app_routes.dart`), never an inline `MaterialPageRoute` in a screen/widget — route construction stays in one place and `lib/widgets` can navigate without importing `lib/screens`. Source-scanned by `test/architecture_test.dart` — [ARCHITECTURE.md §10](ARCHITECTURE.md).
- **Bottom sheets use `showAppBottomSheet`** (`lib/widgets/app_bottom_sheet.dart`), never `showModalBottomSheet` directly — [ARCHITECTURE.md §2](ARCHITECTURE.md).
- **Snackbars use `showTimedSnackBar`** (`lib/widgets/timed_snackbar.dart`), never `showSnackBar` directly — ensures the close icon and framework auto-dismiss (`persist: false`) are always present — [ARCHITECTURE.md §11](ARCHITECTURE.md).
- **Primary form actions (Save / Start) stay tappable while disabled** (*Mechanism A*): pass `onPressed: null`, with a transparent overlay that shows a `showTimedSnackBar` explaining *why*. Use the shared `DisabledTappableButton` (`lib/widgets/disabled_tappable_button.dart`) rather than re-wiring `DisabledTapDetector` by hand — [ARCHITECTURE.md §2](ARCHITECTURE.md).
- **Any platform side-effect goes through a `Provider`** (share sheet, file picker, save-to-device, update check — `lib/state/platform_io_providers.dart` over `lib/services/`), overridden in tests via `ProviderScope`/`ProviderContainer`. Never inject test behaviour through `@visibleForTesting` constructor params or runtime debug branches — that ships a dead branch + a test-only API — [ARCHITECTURE.md §11](ARCHITECTURE.md).
- **Accessible by default**: interactive tiles use `MergeSemantics` + tooltip or `Semantics(button)`; layout spacers use `ExcludeSemantics`; section titles use `Semantics(header: true)` (`FormSectionCard` does this automatically). `test/a11y_test.dart` pumps every screen and gates the a11y guidelines — [ARCHITECTURE.md §2](ARCHITECTURE.md).
- **UI strings Dutch, code identifiers English** — [ARCHITECTURE.md §1](ARCHITECTURE.md).
- **Append a `StorageMigration` step + bump `currentStorageVersion`** when changing stored game-history JSON (frozen, sequenced steps — [`lib/state/migrations.dart`](lib/state/migrations.dart)) — [ARCHITECTURE.md §9](ARCHITECTURE.md).
- **Append a `SettingsMigration` step + bump `currentSettingsVersion`** when changing the `settings` JSON blob (same frozen/sequenced rules — [`lib/state/settings_migrations.dart`](lib/state/settings_migrations.dart)) — [ARCHITECTURE.md §9](ARCHITECTURE.md).
- **Append a `BackupMigration` step + bump `currentBackupVersion`** when changing the ZIP envelope structure (same frozen/sequenced rules — [`lib/state/backup_migrations.dart`](lib/state/backup_migrations.dart)) — [ARCHITECTURE.md §9](ARCHITECTURE.md).
- **`lib/models/game_constraints.dart` (pure) is the single source of truth for valid game data** — name-length consts + the rules as predicates/normalizers (trim, non-empty, case-insensitive uniqueness). The engine asserts, the `validation.dart` import/write gate, and the create/edit UI all compose these; never re-derive a rule or re-declare a limit — [ARCHITECTURE.md §9](ARCHITECTURE.md).
- **Validate untrusted data once, at the boundary, then trust the typed result** — imports and stored JSON are validated where they are decoded (`BackupCodec.decode` / `validation.dart` + `assertGameInvariants`); downstream code (e.g. `applyImport`) does not re-decode or re-validate. Don't add defensive re-checks past the boundary — [ARCHITECTURE.md §2](ARCHITECTURE.md).

## ARCHITECTURE.md reference index

Look up the relevant section before touching that area:

| Topic | Section |
|-------|---------|
| Game shape (4 players, 12 rounds, per-chooser quota) | §1, §5 |
| Design principles & layer architecture (UUID identity, sealed types, single sources of truth, error-throwing lookups, downward-only deps) | §2, §3 |
| File and folder placement (directory map) | §4 |
| Scoring engine & doubling math | §6 |
| Seat relationships (`dealerIndexFor`, `starterIndexFor`) | §5 |
| State machine transitions, autosave; `CalculatorState` sealed (`NoSession`/`ActiveSession`); derived lists must keep stable `select()` identity | §7 |
| Game-rule variants (`RuleVariants`, per-session + app-wide defaults) | §5, §7 |
| End-to-end user flows (tracing a change through layers) | §8 |
| Storage format, migration rules, backup/import | §9 |
| UI layer (routing, screen responsibilities, doubles picker) | §10 |
| Testing conventions (timers, provider overrides, fixture construction) | §11 |
| Build, run & release (commands, CI gates, versioning, fonts/icons/splash, screenshots, deps) | §12 |
| Deferred dependency/toolchain upgrades (blocked AGP / `file_picker`) | §13 |
| Full invariant list with reasoning | §14 |
| Dutch ↔ English glossary (game terms, screen labels, mini-game names) | §15 |
