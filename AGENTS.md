# AGENTS.md

Bonken — offline score calculator (Flutter PWA + Android + iOS/iPadOS) for the
Dutch 4-player card game Bonken. Pure Dart domain → Riverpod state → Material 3 UI.

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

CI's [`verify`](.github/actions/verify/action.yml) action enforces **three
gates, in order**: format check → `flutter analyze --fatal-infos` →
`flutter test`. Run all three locally. analyze + test are NOT enough —
**formatting drift fails CI too**, so always run `fvm dart format .`.

The analyzer is **strict** — the full, authoritative rule set is
[`analysis_options.yaml`](analysis_options.yaml) (rationale in
[ARCHITECTURE.md §12](ARCHITECTURE.md)). The verify gate also runs
`dart fix --dry-run` and fails on any proposed change. Write explicit types and
return types, wrap fire-and-forget futures in `unawaited(...)`, then run
`fvm dart fix --apply` + `fvm dart format .` before pushing.

**Always check `AGENTS.md` and `ARCHITECTURE.md` on every task** — if the change
affects anything documented here, update it inline. Do not defer to a follow-up.

**Add or update tests to cover every changed behaviour.** Check existing coverage
for the area you touched and fill gaps — [ARCHITECTURE.md §11](ARCHITECTURE.md)
for testing conventions (timer stubs, provider overrides, fixture helpers).

## Conventions (do not break)

- **Key per-round data by player UUID**, never seat index — derive indices on demand — [ARCHITECTURE.md §2](ARCHITECTURE.md).
- **Screens use `AppScaffold`**; icons are `Symbols.*` only (never `Icons`) — [ARCHITECTURE.md §2](ARCHITECTURE.md).
- **Bottom sheets use `showAppBottomSheet`** (`lib/widgets/app_bottom_sheet.dart`), never `showModalBottomSheet` directly — [ARCHITECTURE.md §2](ARCHITECTURE.md).
- **Snackbars use `showTimedSnackBar`** (`lib/widgets/timed_snackbar.dart`), never `showSnackBar` directly — ensures the close icon and web auto-dismiss timer are always present — [ARCHITECTURE.md §10](ARCHITECTURE.md).
- **Primary form actions (Save / Start) pass `onPressed: null` when the form is invalid**, but a transparent `DisabledTapDetector` overlay (`lib/widgets/disabled_tap_detector.dart`) sits on top and calls `showIncompleteFormSnackBar` with a reason, so the user learns *why* nothing happened — [ARCHITECTURE.md §2](ARCHITECTURE.md).
- **Any platform side-effect goes through a `Provider`** (e.g. share sheet, file picker, save-to-device — `lib/state/platform_io_providers.dart`, over `lib/services/`), overridden in tests via `ProviderScope`/`ProviderContainer`. Never inject test behaviour through `@visibleForTesting` constructor params or runtime debug branches — that ships a never-taken branch + a test-only API. (`@visibleForTesting` on a *pure function production also calls* is fine; it only relaxes visibility) — [ARCHITECTURE.md §11](ARCHITECTURE.md).
- **Accessible by default**: interactive tiles use `MergeSemantics` + tooltip or `Semantics(button)`; invisible layout spacers use `ExcludeSemantics`; section titles use `Semantics(header: true)` (`FormSectionCard` does this automatically). `test/a11y_test.dart` gates four guidelines — [ARCHITECTURE.md §2](ARCHITECTURE.md).
- **UI strings Dutch, code identifiers English** — [ARCHITECTURE.md §1](ARCHITECTURE.md).
- **Append a `StorageMigration` step + bump `currentStorageVersion`** when changing stored game-history JSON (frozen, sequenced steps — [`lib/state/migrations.dart`](lib/state/migrations.dart)) — [ARCHITECTURE.md §9](ARCHITECTURE.md).
- **Append a `SettingsMigration` step + bump `currentSettingsVersion`** when changing the `settings` JSON blob (same frozen/sequenced rules — [`lib/state/settings_migrations.dart`](lib/state/settings_migrations.dart)) — [ARCHITECTURE.md §9](ARCHITECTURE.md).
- **Append a `BackupMigration` step + bump `currentBackupVersion`** when changing the ZIP envelope structure (same frozen/sequenced rules — [`lib/state/backup_migrations.dart`](lib/state/backup_migrations.dart)) — [ARCHITECTURE.md §9](ARCHITECTURE.md).
- **`lib/models/game_constraints.dart` (pure) is the single source of truth for valid game data** — name-length consts + the rules as predicates/normalizers (trim, non-empty, case-insensitive uniqueness). The engine asserts, the `validation.dart` import/write gate, and the create/edit UI all compose these; never re-derive a rule or re-declare a limit — [ARCHITECTURE.md §9](ARCHITECTURE.md).

## ARCHITECTURE.md reference index

Look up the relevant section before touching that area:

| Topic | Section |
|-------|---------|
| Game shape (4 players, 12 rounds, per-chooser quota) | §1, §5 |
| Design principles (UUID identity, sealed types, single sources of truth, error-throwing lookups) | §2 |
| File and folder placement (directory map) | §4 |
| Scoring engine & doubling math | §6 |
| Seat relationships (`dealerIndexFor`, `starterIndexFor`) | §5 |
| State machine transitions, autosave; `CalculatorState` sealed (`NoSession`/`ActiveSession`); derived lists must keep stable `select()` identity | §7 |
| Game-rule variants (`RuleVariants`, per-session + app-wide defaults) | §5, §7 |
| End-to-end user flows (tracing a change through layers) | §8 |
| Storage format, migration rules, backup/import | §9 |
| UI layer (routing, screen responsibilities, doubles picker) | §10 |
| Testing conventions (timers, provider overrides, fixture construction) | §11 |
| Full invariant list with reasoning | §14 |
| Dutch ↔ English glossary (game terms, screen labels, mini-game names) | §15 |
