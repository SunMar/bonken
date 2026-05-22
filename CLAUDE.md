# CLAUDE.md

Bonken — offline score calculator (Flutter PWA + Android) for the Dutch
4-player card game Bonken. Pure Dart domain → Riverpod state → Material 3 UI.

**Full architecture & rationale: [ARCHITECTURE.md](ARCHITECTURE.md).** Player-facing docs
(Dutch): [README.md](README.md).

## Commands

```bash
flutter pub get
flutter test                                       # full suite
flutter analyze --fatal-infos                      # static analysis (CI fails on infos)
dart format .                                       # auto-format (run before committing)
dart format --output=none --set-exit-if-changed .  # formatting check (CI gate)
```

Flutter is pinned in `.fvmrc` (3.41.9); CI installs from there. Bare
`flutter`/`dart` work locally; use `fvm flutter <cmd>` to match the pin exactly.

## Before you finish

CI's [`verify`](.github/actions/verify/action.yml) action enforces **three
gates, in order**: format check → `flutter analyze --fatal-infos` →
`flutter test`. Run all three locally. analyze + test are NOT enough —
**formatting drift fails CI too**, so always run `dart format .`.

The analyzer is strict (`analysis_options.yaml`): strict casts/inference/
raw-types, required trailing commas, explicit return types, no `dynamic`
calls. Write explicit types; let `dart format` add the trailing commas.

## Conventions (do not break)

- **4 players, 12 rounds** (`playerCount`, `GameSession.totalRounds`).
- **Key per-round data by player UUID**, never seat index — derive indices on demand.
- **Σ scores == `totalPoints`** per game (engine invariant, asserted).
- **Seat math only in `lib/models/game_mechanics.dart`** (`dealerIndexFor`).
- **Screens use `AppScaffold`**; icons are `Symbols.*` only (never `Icons`).
- **UI strings Dutch, code identifiers English.**
- **Bump `_currentVersion` + add a migration** when changing stored JSON.

Full invariant list + the "why": [ARCHITECTURE.md §13](ARCHITECTURE.md).
