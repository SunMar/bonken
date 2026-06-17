# AGENTS.md

Bonken — offline score calculator (Flutter PWA + Android) for the Dutch
4-player card game Bonken. Pure Dart domain → Riverpod state → Material 3 UI.

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

**Update `AGENTS.md` and `ARCHITECTURE.md` as part of the change** when it
affects documented architecture, conventions, the storage version, the directory
map, or invariants — not as a follow-up.

## Conventions (do not break)

- **4 players, 12 rounds** (`playerCount`, `GameSession.totalRounds`).
- **Key per-round data by player UUID**, never seat index — derive indices on demand.
- **Σ scores == `totalPoints`** per game (engine invariant, asserted).
- **Seat-relationship formulas only in `lib/models/game_mechanics.dart`**
  (`dealerIndexFor` / `starterIndexFor`); `List<Player>` lookups/rotations
  (`seatIndexOf`, `rotatedFromDealer`) are utilities that live with `Player`.
- **`gameById` and `seatIndexOf` throw on unknown ids** — no silent fallback.
  Unknown ids from stored JSON hit `_validateReferences` in `GameSession.fromJson`
  first; the `on Object` catch in `GameHistoryNotifier.build()` converts them to
  `CorruptStorageException`. Unknown ids after a successful load are programming
  errors — throwing makes them loud.
- **Screens use `AppScaffold`**; icons are `Symbols.*` only (never `Icons`).
- **Bottom sheets use `showAppBottomSheet`** (`lib/widgets/app_bottom_sheet.dart`), never `showModalBottomSheet` directly.
- **Platform side-effects (share sheet, file picker) go through a `Provider`** (`lib/state/platform_io_providers.dart`, over `lib/services/`), overridden in tests via `ProviderScope`/`ProviderContainer`. Never inject test behaviour through `@visibleForTesting` constructor params or runtime debug branches — that ships a never-taken branch + a test-only API. (`@visibleForTesting` on a *pure function production also calls* is fine; it only relaxes visibility.) See [ARCHITECTURE.md §11](ARCHITECTURE.md).
- **Accessible by default** ([ARCHITECTURE.md §2](ARCHITECTURE.md)): interactive
  tiles use `MergeSemantics` + tooltip or `Semantics(button)`; invisible layout
  spacers use `ExcludeSemantics`; **section titles wrapped in
  `Semantics(header: true)`** (`FormSectionCard` does this automatically).
  `test/a11y_test.dart` gates four guidelines.
- **UI strings Dutch, code identifiers English.**
- **Append a `StorageMigration` step (`lib/state/migrations.dart`) + bump `currentStorageVersion`** when changing stored game-history JSON (frozen, sequenced steps).
- **Append a `SettingsMigration` step (`lib/state/settings_migrations.dart`) + bump `currentSettingsVersion`** when changing the `settings` JSON blob (same frozen/sequenced rules — see [ARCHITECTURE.md §9](ARCHITECTURE.md)).
- **Append a `BackupMigration` step (`lib/state/backup_migrations.dart`) + bump `currentBackupVersion`** when changing the ZIP envelope structure (same frozen/sequenced rules — see [ARCHITECTURE.md §9](ARCHITECTURE.md)).
- **Import settings through notifier setters** (`setMode`, `setValue`), never `ref.invalidate` — invalidating settings providers rebuilds from the old startup value and silently drops the import.
- **Game-rule variants** live in `lib/models/` (one enum each), grouped into a
  `RuleVariants` (`lib/models/rule_variants.dart`) carried by `GameSession` +
  `CalculatorState`; per-variant app-wide defaults in
  `lib/state/default_*_variant_provider.dart`, pre-loaded in `main()`.
- **`lib/models/game_constraints.dart` (pure) is the single source of truth for
  valid game data** — name-length consts + the rules as predicates/normalizers
  (trim, non-empty, case-insensitive uniqueness). The engine asserts, the
  `validation.dart` import/write gate, and the create/edit UI all compose these;
  never re-derive a rule or re-declare a limit. Enum/settings/manifest checks
  stay in `validation.dart`. Details: [ARCHITECTURE.md §9](ARCHITECTURE.md).

Full invariant list + the "why": [ARCHITECTURE.md §14](ARCHITECTURE.md).
