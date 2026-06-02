# Bonken — Architecture & Design Specification

> Engineering reference for developers and coding agents working in this repo.
> This document is the authoritative *deep* reference (how the code is built and
> why); for the day-to-day quick-start (commands, CI gates, top invariants) see
> [`CLAUDE.md`](CLAUDE.md), which is auto-loaded by coding agents and points
> here for detail. For player-facing install/play docs (in Dutch), see
> [`README.md`](README.md); the in-app rules text lives in
> [`lib/data/game_rules.dart`](lib/data/game_rules.dart).

**Contents:** 1. Overview · 2. Design philosophy · 3. Architecture · 4. Directory
map · 5. Domain model · 6. Scoring & doubling · 7. State management · 8. Key
flows · 9. Persistence & migration · 10. UI layer · 11. Testing · 12. Build &
release · 13. Conventions & invariants · 14. Glossary

---

## 1. Overview

Bonken is a **score calculator** for the Dutch four-player trick-taking card
game **Bonken**. It is *not* a game engine — it does not deal cards, enforce
legal plays, or simulate tricks. People play the physical card game; the app
records, per round, *who chose which mini-game*, the *doubling* between players,
and the *per-player result* (tricks won / penalty cards / who won a specific
trick), then computes per-round and cumulative scores.

Key characteristics:

- **Platform:** Flutter. Ships as an offline-first **PWA** (web, installable on
  Android/iOS/desktop) and as a native Android APK.
- **Fully offline / local-only:** no backend, no accounts, no network in the
  core flow. All data is in `SharedPreferences`. Fonts and licenses are bundled
  as assets so the app works with zero connectivity. (The only network use is an
  optional Android in-app-update check, which never blocks startup.)
- **Language split:** **UI strings are Dutch**, **all code identifiers are
  English**. e.g. the class `KingOfHearts` carries `name: 'Harten Heer'`. When
  reading the code, expect English symbols; when reading the screen, expect
  Dutch — the [glossary](#14-glossary-dutch--english) bridges the two.
- **Shape of a game:** always **4 players**, exactly **12 rounds**. Each round
  one player (the *chooser* / *kiezer*) picks one mini-game from a catalog of
  **13**.
- **License:** AGPL-3.0 (registered in-app via `showLicensePage`).

---

## 2. Design philosophy

These are the load-bearing principles. Internalize them before changing code —
most of the structure exists to serve one of these.

- **Identity by UUID, never by seat index.** Each `Player` gets a stable v4
  UUID at creation ([`lib/models/player.dart`](lib/models/player.dart)). Every
  per-round datum — scores, chooser, doubling pairs, input maps — is keyed by
  player UUID. *Why:* players can be **renamed and reordered** mid-game (see
  `EditGameScreen`) without corrupting historical rounds. Seat indices
  (0–3) are derived on demand from IDs and are never persisted.

- **Immutable state + narrow reactivity.** `CalculatorState` is deeply
  immutable (factory + private `._()` constructor + `copyWith`). Widgets watch
  the *minimum* slice via `ref.watch(provider.select(...))`, often a record of
  just the fields they render. *Why:* the round-input screen mutates state on
  every keystroke; narrow selects keep rebuilds local.

- **Stored derived fields for `select()` stability.** Derived lists that
  selectors watch — `playerNames`, `displayedPlayers` — are computed once and
  **stored as `final` fields**, recomputed in `copyWith` only when their inputs
  (`players` / `firstDealerId`) change. *Why:* a getter would return a *new list
  identity* every call, so `select()`'s `==` check would always see "changed"
  and rebuild needlessly.

- **Sealed types for compile-time exhaustiveness.** Unions are `sealed class`
  hierarchies, so `switch` is exhaustive and adding a variant *breaks
  compilation* until every consumer handles it: `GameSymbol`
  (Text/Suit/Icon), `GameInput` (Counts/Recipient) + `InputDescriptor`
  (Counts/Recipient),
  `PendingRoundState` (None/Active), `Block` (rules content).

- **Single sources of truth.** The game catalog is the one list `allGames`
  ([`game_catalog.dart`](lib/models/games/game_catalog.dart)). The
  dealer/chooser/starter seat relationships live *only* in
  [`game_mechanics.dart`](lib/models/game_mechanics.dart) — nothing else
  hardcodes "dealer = chooser − 1".

- **Debug asserts, graceful release.** Invariants use `assert` (compiled out in
  release) *plus* a safe production fallback. e.g. `CalculatorState._indexOf`
  asserts an ID is found but falls back to `0`; `_recalculate` asserts the score
  sum equals `totalPoints`. Bugs crash loudly in dev, degrade quietly in prod.

- **Pure domain, no framework leakage.** `lib/models/**` imports no Riverpod and
  (almost) no Flutter — the scoring engine is plain Dart and unit-testable in
  isolation. State depends on models; UI depends on state and models; nothing
  points back up.

- **Material 3, themed centrally.** Colors M3's `ColorScheme` doesn't cover
  (warnings, card suits, double-states, score sign) are `ThemeExtension`s in
  [`app_theme_extensions.dart`](lib/theme/app_theme_extensions.dart).
  Iconography is **Material Symbols only** (`Symbols.*`); the legacy `Icons`
  set is never used (even auto-generated back/close/drawer buttons are remapped
  in `main.dart`).

- **Screens are guarded.** Every full-screen route uses `AppScaffold` (wraps the
  body in `SafeArea` for edge-to-edge mode). Enforced by a test —
  [`test/architecture_test.dart`](test/architecture_test.dart).

- **Bottom sheets are guarded.** All modal bottom sheets call
  `showAppBottomSheet` (wraps content in a `Padding` sized to
  `MediaQuery.viewPaddingOf.bottom`, clearing the system navigation bar;
  always enables `isScrollControlled` and `useSafeArea`). Direct calls to
  `showModalBottomSheet` are forbidden and caught by the same test in
  [`test/architecture_test.dart`](test/architecture_test.dart).

- **Guide with the rules, don't hard-enforce them.** The app *surfaces* the
  game's rules (amber `Note` callouts, disabled-looking affordances) but lets
  players override them — *what happens at the physical table is authoritative,
  not what the app thinks is legal*. Concretely: the per-chooser game quota is a
  **soft** disable with a "Toch doorgaan" dialog (`game_screen.dart`); the two
  doubling rules the picker would otherwise block — a redouble whose turn has
  passed, and the chooser initiating a double — are shown disabled but
  **force-able** via a confirm dialog (`doubles_picker.dart`); rule prose is data
  shown verbatim, not branching logic (§6). Code only **hard**-enforces what
  keeps data well-formed (e.g. a canonical `DoubleMatrix`, Σ scores ==
  `totalPoints`), never table etiquette.

- **Accessible by default.** Decorative `Icon`s carry no `semanticLabel`, so
  they stay out of the a11y tree; every interactive control exposes a button
  role + label — icon buttons via `tooltip`, custom `InkWell` tiles via an
  explicit `Semantics` (with `MergeSemantics` so each reads as one control).
  Dimmed-but-tappable overrides (doubles force tiles, played/quota game tiles)
  announce as *enabled* buttons with a hint, since the dimming is purely
  visual. Tap targets are kept at the standard ≥48dp. **Section and card titles
  must be wrapped in `Semantics(header: true)`** — the `FormSectionCard` widget
  does this automatically; hand-written cards must add it explicitly. Invisible
  layout spacers use `ExcludeSemantics`. `test/a11y_test.dart` pumps every
  screen with semantics on and gates `textContrastGuideline`,
  `labeledTapTargetGuideline`, and `android`/`iOSTapTargetGuideline` via the
  normal `flutter test` run (no separate CI step).

---

## 3. Architecture at a glance

Three layers; dependencies point **downward only**:

```
            ┌─────────────────────────────────────────────┐
  UI        │  lib/screens/*  +  lib/widgets/*             │  ConsumerWidgets
            │  watch providers · call notifier methods     │
            └───────────────┬─────────────────────────────┘
                            │ ref.watch(provider.select) / ref.read(...notifier)
            ┌───────────────▼─────────────────────────────┐
  STATE     │  lib/state/*  (Riverpod Notifiers)           │
            │  calculatorProvider · gameHistoryProvider ·  │
            │  themeModeProvider                           │
            └───────────────┬─────────────────────────────┘
                            │ construct/read models · toJson/fromJson
            ┌───────────────▼─────────────────────────────┐
  MODELS    │  lib/models/*  (pure Dart, no UI)            │
            │  MiniGame scoring engine · session · doubles │
            └─────────────────────────────────────────────┘
```

- **Models** are plain data + pure functions; the scoring engine lives here.
- **State** orchestrates: `CalculatorNotifier` mutates the in-memory round; a
  debounced autosave serializes the live session into `gameHistoryProvider`,
  which owns persistence.
- **UI** is declarative: it renders `CalculatorState` / history and calls
  notifier methods on interaction.

**Two providers, two responsibilities.** `calculatorProvider` holds the *one
game currently being played/edited* (transient, in-memory). `gameHistoryProvider`
holds *all saved games* (the persisted list). The bridge between them is
`CalculatorNotifier.buildSession()` → `gameHistoryProvider.saveGame()`, driven
automatically by the autosave debounce.

End-to-end for a completed round: user input → `updateInput` → `_recalculate`
(runs `MiniGame.calculateScores`) → new `state` → overridden `set state`
schedules a 400 ms debounced autosave → `buildSession()` → `saveGame()` →
`SharedPreferences`.

---

## 4. Directory map (`lib/`)

```
lib/
  main.dart                  Entry: theme, forced-nl localization, routing/deep links,
                             license registration, edge-to-edge, Android update check.
  utils.dart                 Cross-cutting helpers: formatDate/formatScore, scoreColor,
                             disabledOnSurface, reorder index math, shared string constants.

  models/                    Pure domain layer (no Riverpod; minimal Flutter).
    mini_game.dart           MiniGame abstract base + calculateScores engine; GameSymbol
                             sealed union; GameCategory; playerCount(4); doublingTurnIndex.
    game_mechanics.dart      dealerIndexFor / starterIndexFor — ONLY home of seat relationships.
    input_descriptor.dart    Sealed GameInput (CountsInput/RecipientInput) + sealed InputDescriptor.
    player.dart              Player (stable UUID id + name).
    double_matrix.dart       DoubleMatrix: per-pair doubling state + initiator, UUID-keyed.
    score_result.dart        ScoreResult: {playerId: pointsThisRound}.
    round_record.dart        RoundRecord: one completed round (in-memory + toJson).
    game_session.dart        GameSession aggregate + PendingRound; derived totals/winners; JSON.
    rule_variants.dart       RuleVariants: per-game StarterVariant + HeartsVariant, grouped + JSON.
    games/
      game_catalog.dart      allGames — the single ordered list of all 13 mini-games.
      positive_games.dart    PositiveGame base + Clubs/Diamonds/Hearts/Spades/NoTrump.
      negative_games.dart    The 8 negative mini-games.

  state/                     Riverpod providers.
    calculator_provider.dart CalculatorState + CalculatorNotifier (the in-game state machine).
    game_history_provider.dart Persistence (SharedPreferences) + versioning; runs migrations on load.
    migrations.dart          Sequenced, frozen StorageMigration steps (v1→v2→v3→v4→v5→v6) + runner.
    theme_mode_provider.dart Light/dark/system theme, persisted; pre-loaded in main().
    default_starter_variant_provider.dart  App-wide default StarterVariant; pre-loaded in main().
    default_hearts_variant_provider.dart   App-wide default HeartsVariant; pre-loaded in main().
    enum_preference_notifier.dart  Generic EnumPreferenceNotifier<T> base + loadPersistedEnum().
    rules_locked_provider.dart  bool (default false); true while rules are shown for a fixed
                             in-game rule set. Overridden by RulesIconButton for the pushed route.

  screens/                   Full-screen routes (all use AppScaffold).
    home_screen.dart         Start: saved-games list, "Nieuw spel", theme menu; resume/delete+undo.
    new_game_screen.dart     Enter names (with suggestions) + pick first dealer + pick variants.
    game_screen.dart         In-game hub: game selection, live scoreboard, history, edit/delete.
    round_input_screen.dart  Per-round: chooser, doubles, input form, live/final result.
    edit_game_screen.dart Rename/reorder players + change first dealer + change variants mid-game.
    rules_screen.dart        Renders rules content (full doc or single game); variant text and
                             whether the alternative is shown come from the variant providers +
                             rulesLockedProvider (overridden per-route when opened in-game).
    settings_screen.dart     App-wide default settings: StarterVariant + HeartsVariant.

  widgets/                   Reusable UI.
    app_scaffold.dart        SafeArea-wrapping Scaffold (mandatory for screens).
    app_bottom_sheet.dart    showAppBottomSheet — viewPadding-aware
                             showModalBottomSheet wrapper (mandatory for all
                             modal bottom sheets).
    scoreboard_card.dart     The player/score grid used on home + game screens.
    score_result_view.dart   Per-player score outcome card (final or partial);
                             trophy Opacity for stable layout, doubles chips.
                             Used in RoundInputScreen.
    doubles_picker.dart      Two-panel interactive doubling editor (initiators × targets).
    doubles_chips.dart       Read-only doubling summary chips (history view).
    double_state_chip.dart   Shared M3 chip for double/redouble state pills
                             (no border, compact density, bold labelMedium).
                             Used by doubles_chips.dart and doubles_picker.dart.
    selectable_player_tile.dart  Shared selectable tile (player pickers + doubles initiators).
    game_avatar.dart         GameAvatar (circular mini-game symbol avatar) + the
                             _GameSymbol renderer; used by the game / round-input screens.
    app_bar_widgets.dart     Reusable AppBar building blocks: AboutIconButton
                             (leading info icon → About dialog), RulesIconButton
                             (pushes RulesScreen, optionally scoped to one game; wraps the
                             pushed route in a ProviderScope to lock variants when given the
                             session's values), TitleWithRules (AppBar.title with embedded rules
                             icon), SettingsIconButton (pushes SettingsScreen),
                             ThemeMenuButton (MenuAnchor cycling light/dark/system;
                             AlignmentDirectional.bottomEnd — the M3 overflow-menu
                             pattern), and resolveAboutVersionLine() /
                             openAboutDialog() (@visibleForTesting).
    game_rules_card.dart     Tappable "Spelregels" card for new-game and edit-game; summarises
                             how the per-game rules deviate from the player's configured
                             defaults (one row per differing rule, else a "standaardregels"
                             note — there is no canonical rule set). Opens a modal bottom sheet
                             (content-height, drag handle, X close, scrim/swipe/back also
                             dismiss) with the same two FormSectionCard variant sections as
                             SettingsScreen. Selections update the caller's local state
                             immediately; persisted only on Start spel / Opslaan.
    variant_radio_list.dart  Generic RadioGroup<T extends LabeledVariant> (label + description per
                             value); used by settings, new-game, edit-game + the rules variant dialog.
    round_meta_line.dart     Wrapping "Kiezer · Deler · Uitkomst" metadata line shared by the
                             game-screen and round-input banners.
    info_banner.dart         Shared secondaryContainer Card with info icon + arbitrary child;
                             used by _RoundInfoBanner (game screen) and _SettingsNote (settings).
    form_section_card.dart   Shared Card + titled section header widget (Semantics(header:true)
                             + subtitle + child); used on new-game, edit-game, settings.
    game_input/              Round-input building blocks: form, counts input, player picker.
    …                        dealer_picker_dialog.dart, dialogs.dart,
                             timed_snackbar.dart + game_deleted_snackbar.dart
                             (cancel-and-replace timer; undo snackbar),
                             amber_warning_box.dart, player_name_field.dart,
                             player_list_field.dart, primary_action_button.dart,
                             rules_block_view.dart, drag_handle.dart,
                             incomplete_form_snackbar.dart.

  models/
    labeled_variant.dart     LabeledVariant interface (label + description) implemented by
                             StarterVariant and HeartsVariant.
    starter_variant.dart     StarterVariant enum (dealerStarts / oppositeChooserStarts).
    hearts_variant.dart      HeartsVariant enum (onlyAfterPlayedHeart / graduatedUnlock).

  data/game_rules.dart       Static rules content (Block/Section/GameSection) for rules_screen.
                             VariantBlock (VariantKind.starter/hearts) carries textFor() and
                             shows a variant picker dialog via a settings icon.
  theme/app_theme_extensions.dart  ThemeExtensions: Warning/GameSuit/DoubleState/Score colors.
  services/app_updater.dart  Fire-and-forget Google Play in-app update check (Android only).
```

---

## 5. Domain model

### `MiniGame` + shape bases ([`mini_game.dart`](lib/models/mini_game.dart))
Abstract base for all 13 games (declares `id`, `name`, `symbol`, `category`,
`pointsPerUnit`, `totalPoints`). It supplies the shared **`calculateScores`**
engine (§6) and defines `GameSymbol` (sealed: `TextSymbol` short label,
`SuitSymbol` ♠♥♦♣ in bundled DejaVu Sans, `IconSymbol` Material Symbol).

Concrete games never extend `MiniGame` directly — they extend one of **two
intermediate bases, one per input shape** (mirroring the sealed `GameInput` /
`InputDescriptor` hierarchies). Each base owns `rawCounts`, `inputDescriptor`,
and the storage round-trip (`inputToCounts` / `countsToInput`, §9); a leaf game
declares only its metadata + the human-facing bits:

| base | in-memory type | leaf supplies | members |
|------|---------------|---------------|---------|
| `CountsMiniGame` | `CountsInput` (`{uuid:int}`, Σ = `total`) | `total`, `unitLabel` | 4 negative counts games + `PositiveGame` (the 5 positives) |
| `RecipientMiniGame` | `RecipientInput` (`List<String?>`, one slot per prompt) | `prompts` | KingOfHearts, FinalTrick, Dominoes, SeventhAndThirteenth |

**`rawCounts(input, players) → {playerId: int}`** is the per-player count used by
scoring: counts games re-key the entered map (absent ⇒ 0); recipient games count
how many slots contain each player UUID (0, 1, or 2 for SeventhAndThirteenth when
the same player wins both tricks).

The **13 games** (catalog order: negatives first, then positives):

| id | name (nl) | category | pointsPerUnit | total | input shape |
|----|-----------|----------|--------------:|------:|-------------|
| `kingOfHearts` | Harten Heer | negative | −100 | −100 | recipient (1 slot) |
| `kingsAndJacks` | Heren / Boeren | negative | −25 | −200 | counts (Σ 8) |
| `queens` | Vrouwen | negative | −45 | −180 | counts (Σ 4) |
| `duck` | Bukken | negative | −10 | −130 | counts (Σ 13) |
| `heartPoints` | Harten punten | negative | −10 | −130 | counts (Σ 13) |
| `seventhAndThirteenth` | 7e / 13e | negative | −50 | −100 | recipient (2 slots) |
| `finalTrick` | Laatste slag | negative | −100 | −100 | recipient (1 slot) |
| `dominoes` | Domino | negative | −100 | −100 | recipient (1 slot) |
| `clubs` | Klaveren ♣ | positive | +20 | +260 | counts (Σ 13) |
| `diamonds` | Ruiten ♦ | positive | +20 | +260 | counts (Σ 13) |
| `hearts` | Harten ♥ | positive | +20 | +260 | counts (Σ 13) |
| `spades` | Schoppen ♠ | positive | +20 | +260 | counts (Σ 13) |
| `noTrump` | Zonder troef | positive | +20 | +260 | counts (Σ 13) |

> The catalog has **13** games but a session plays **12 rounds** — all 8
> negative plus 4 of the 5 positive games (one positive is left unplayed).
> **Per-chooser quota:** each player may choose at most **1 positive** and **2
> negative** games. Enforced softly in `game_screen.dart` (tile disabled with an
> override dialog), not in the model.

### `GameInput` + `InputDescriptor` ([`input_descriptor.dart`](lib/models/input_descriptor.dart))
**`GameInput`** is a sealed class with two variants that carry the typed
in-memory round input — no string keys, no `dynamic`:

```dart
// CountsInput — per-player tally; Σ must equal total
CountsInput({"<uuidA>": 5, "<uuidB>": 4, "<uuidC>": 3, "<uuidD>": 1})
// isEmpty = Σ == 0    isComplete = Σ == total

// RecipientInput — one slot per prompt (null = not yet selected)
RecipientInput(["<uuidB>"])                  // single-slot game
RecipientInput(["<uuidA>", "<uuidC>"])       // two-slot game (7e/13e)
RecipientInput([null, "<uuidC>"])            // half-filled two-slot
```

**`InputDescriptor`** is sealed; tells the UI what form to render *without*
knowing concrete game types. `CountsInputDescriptor` and
`RecipientInputDescriptor` each implement `isEmpty(GameInput)`,
`isComplete(GameInput)`, and `defaults(players) → GameInput`.

> The **persisted** form is not `GameInput` — on disk every game's input
> collapses to the uniform structure `{"counts": [ {uuid:int}, … ]}` (§9).
> Conversion happens at the serialization boundary via `inputToCounts` /
> `countsToInput` on the `MiniGame` bases.

### `Player` ([`player.dart`](lib/models/player.dart))
`{id: UUIDv4, name}`. `==`/`hashCode` over both fields; `copyWith` preserves the
id. The public constructor mints a new UUID; the private `Player._` (used by
`fromJson` and migration) keeps an existing one.

### `DoubleMatrix` ([`double_matrix.dart`](lib/models/double_matrix.dart))
Immutable map of the (up to) 6 player-pairs → a unified record
`({DoubleState state, String initiator})`. Absence means `none`; every entry
in the map has a non-none state and a known initiator by construction.
Pair keys are **canonicalized** (lexicographically smaller UUID first) so
lookups are order-independent. `multiplierFor` → 0 / 1 / 2 (the only thing
scoring needs); the initiator drives UI direction labels and who is allowed to
redouble, but does **not** affect the score. `hasAnyDouble` gates
serialization. JSON: `"uuidA,uuidB": {"state": …, "initiator": …}`. Value-equality
+ hashCode are implemented so `select()` / `copyWith` short-circuits work.

### `ScoreResult` ([`score_result.dart`](lib/models/score_result.dart))
`{playerId: pointsThisRound}` (already multiplied to points). Value equality so
`_recalculate` can skip no-op emissions.

### `RoundRecord` ([`round_record.dart`](lib/models/round_record.dart))
One completed round: `roundNumber`, the full `game` object, `chooserId`,
`scoresByPlayer`, the in-memory `input`, and `doubles`. `toJson()` (scores under
`'scores'`) serializes `input` through `game.inputToCounts` to the uniform
`{"counts":[…]}` form (§9). There is **no `fromJson`** — deserialization needs the
catalog to turn `gameId` back into a `MiniGame` (and that game to rebuild the
in-memory input via `countsToInput`), so it lives on `GameSession._roundFromJson`,
keeping `RoundRecord` a catalog-free data class.

### `GameSession` + `PendingRound` ([`game_session.dart`](lib/models/game_session.dart))
The persisted aggregate: `id`, `createdAt`/`updatedAt`, `players`,
`firstDealerId`, `ruleVariants` (a `RuleVariants` grouping the per-game
`starterVariant` + `heartsVariant`), `rounds: List<RoundRecord>`,
optional `pendingRound`.
Lazily-computed (`late final`) derived getters: `isFinished` (≥ `totalRounds`
== 12), `finalScoresByPlayer`, `winnerIds`, and the display-ordered
`displayedPlayers` / `displayedPlayerNames` / `displayedScores` /
`displayedWinnerIndices` (rotated so the round-1 dealer is first). `fromJson`
resolves each round's `gameId` against `allGames`.
**`PendingRound`** is a round started but not yet scored — it stores
`gameId`/`gameName` strings + `input` + optional `doublesJson` so partial work
survives an app restart. Its `toJson`/`fromJson` resolve the game by `gameId` to
convert `input` to/from the uniform counts form, same as a round.

### `game_mechanics.dart` ([`game_mechanics.dart`](lib/models/game_mechanics.dart))
`dealerIndexFor(chooserIndex) = (chooserIndex − 1) mod 4` (the dealer sits to the
chooser's right; equivalently the chooser is left of the dealer).
`starterIndexFor(chooserIndex, StarterVariant)` — the seat index of the player
who leads the first trick: `dealerStarts` → same as the dealer; `oppositeChooserStarts`
→ `(chooserIndex − 2) mod 4`. Both seat relationships live here so this file
remains the single home for all seat arithmetic.
`playerCount` (4) and `doublingTurnIndex` live in `mini_game.dart`. The dealer
for round *N* is `players[(firstDealerIndex + N − 1) mod 4]`. **Change these
formulas here and nowhere else.**

---

## 6. Scoring & doubling (deep-dive)

### The engine

All scoring funnels through `MiniGame.calculateScores`. For each player *i*:

```
effectiveCount(i) = rawCount(i)
                  + Σ_{j ≠ i} ( rawCount(i) − rawCount(j) ) × multiplier(i, j)

score(i) = effectiveCount(i) × pointsPerUnit
```

where `multiplier(i, j)` comes from the `DoubleMatrix`:

| DoubleState | multiplier | meaning |
|-------------|:----------:|---------|
| `none`      | 0 | pair ignored in settlement |
| `doubled`   | 1 | pair difference counted once |
| `redoubled` | 2 | pair difference counted twice |

**Intuition.** With no doubles, `effectiveCount == rawCount` and you get the
classic straight score (count × points). A double between A and B layers on a
*zero-sum side bet on their difference*: the player with the better result in
that pair gains `|rawA − rawB| × mult` units; the other loses the same.
Redoubling ("teruggaan") doubles that side bet. **Direction doesn't matter** —
who initiated the double has no effect on the math; only the pair's state and the
two raw counts do.

Because every pair contributes `+x` to one player and `−x` to the other, the
grand total is **invariant** under any doubling:

```
Σ_i score(i) == Σ_i rawCount(i) × pointsPerUnit == totalPoints
```

This is asserted (debug-only) in `CalculatorNotifier._recalculate` right after a
complete result is computed — a mismatch means a scoring bug and crashes early in
development while degrading gracefully in release.

### Worked example (Harten, +20/trick)

Four players A, B, C, D win **2, 7, 3, 1** tricks (Σ = 13). B doubles A.

| scenario | A | B | C | D | Σ |
|----------|---:|---:|---:|---:|---:|
| no doubles | 40 | 140 | 60 | 20 | 260 |
| B–A `doubled` (m=1):  A = (2 + (2−7)) ×20 = −60;  B = (7 + (7−2)) ×20 = 240 | −60 | 240 | 60 | 20 | 260 |
| A goes back → `redoubled` (m=2):  A = (2 + 2(2−7)) ×20 = −160;  B = (7 + 2(7−2)) ×20 = 340 | −160 | 340 | 60 | 20 | 260 |

C and D are untouched (not in any double) and the total stays 260 throughout.

### How doubling is represented & enforced

The data model is `DoubleMatrix` (§5): a value type mapping canonical
player-pairs to a `({state, initiator})` record. **Scoring reads only
`multiplierFor` (0/1/2)** — the initiator exists purely so the UI can label
direction and decide who may still redouble; it never affects the math.

The rule *prose* is data, not logic: it lives in `kDubbelenSection`
(`game_rules.dart`) and is surfaced verbatim as amber `Note` warnings on
`RoundInputScreen`. The app's posture is to **show** the table rules and let
players self-police, encoding in code only the constraints needed to keep the
`DoubleMatrix` well-formed. Those live in `DoublesPicker`, which edits a copy and
emits it via `onChanged` → `updateDoubles`:

| Constraint (game rule) | Where it's encoded |
|---|---|
| Turn order: left-of-chooser first, chooser last | `doublingTurnIndex` / `DoublesPicker._doublingOrder` (start `(chooserIndex+1)%4`); drives panel ordering *and* redouble eligibility |
| Per-pair state machine | `_cycle`: initiator side `none→doubled→redoubled→none`; target side toggles `doubled↔redoubled` |
| Redouble only while your turn hasn't passed | `_turnIndex` gates `canRedouble`; once passed the tile is shown disabled but **force-able** via a confirm dialog (`_confirmForce`) — guide-don't-enforce (§2) |
| Chooser may not initiate (only "go back") | `isChooserInitiating` guard; the tile is shown disabled but **force-able** via a confirm dialog (`_confirmForce`) — guide-don't-enforce (§2) |
| Bulk *Zaal* / *Slappe hap* / chooser "Terug" | `_applyBulk` / `_toSlappeHap` / `_undoZaalTerug` over computed `zaalTargets` / `slappeHapTargets` |
| Domino Ace/2 precondition | **Not** enforced — surfaced as an amber `Note` only |

`DoublesChips` renders the same `DoubleMatrix` read-only in the history view.

---

## 7. State management

### `calculatorProvider` — the in-game state machine
`NotifierProvider<CalculatorNotifier, CalculatorState>`
([`calculator_provider.dart`](lib/state/calculator_provider.dart)). Holds the
**single game currently being played or edited**.

**`CalculatorState` fields**, grouped:

| group | fields | notes |
|-------|--------|-------|
| identity | `sessionId`, `createdAt`, `updatedAt` | empty `sessionId` ⇒ no active game (autosave off) |
| players | `players`, `playerNames`*, `displayedPlayers`* | *stored derived, for `select()` stability |
| seating | `firstDealerId`, `dealerId`, `chooserId` | IDs; seat indices via `dealerIndex`/`chooserIndex`/`firstDealerIndex`/`displayedChooserIndex` getters |
| progress | `roundNumber` (1–12), `history: List<RoundRecord>` | |
| current slot | `selectedGame`, `input`, `doubles`, `result`, `partialResult` | the round being entered |
| stash | `pending: PendingRoundState` | sealed: `NoPendingRound` \| `ActivePendingRound{game,input,doubles}` |
| edit | `editingRoundIndex`, `editOriginal{Input,Doubles,ChooserId}` | non-null while re-editing a past round |
| rules | `ruleVariants: RuleVariants` | per-game `starterVariant` + `heartsVariant`, grouped (mirrors `GameSession`); `starterIndex` getter reads it |

Helper getters: `hasPendingGame`, `hasMeaningfulPendingInput`, `inputState`
(`InputState{none,partial,complete}` via the descriptor), `isEditingExistingRound`,
`isEditingLastRound`, `canRollbackWithPartial`, and `hasActiveChanges` (deep-equals
current vs. captured originals; gates discard confirmations).

`result` is the **final** score (input complete). `partialResult` is a **live
preview** shown while a counts game is partway entered (0 < sum < total).
`_recalculate` switches on `inputState`: complete → set `result`; partial → set
`partialResult`; none → clear both. It skips emitting when the value is unchanged.

**Notifier methods (the transitions):**
- `startNewGame({players, dealerIndex, ruleVariants})` — fresh session id + reset.
- `loadSession(session)` — restore a saved game; reconstructs `dealerId`/
  `chooserId`/`roundNumber` from `firstDealerId` + history length, and rehydrates
  any `pendingRound` into an `ActivePendingRound`.
- `selectGame(game)` — enter the input slot. If `game` matches the current
  `ActivePendingRound`, it **resumes** (restores stashed input/doubles);
  otherwise it starts fresh (`defaults`, chooser = left of dealer).
- `setChooser` / `updateInput` / `updateDoubles` — edit the slot; each calls
  `_recalculate`.
- `deselectGame()` — the **main exit**, 4 cases:
  1. editing + valid `result` → **replace** the edited round in `history`;
  2. editing + incomplete → falls back to `cancelEditRound`;
  3. new + `result` → **append** to `history`, advance dealer/round;
  4. new + partial input → **stash** as `ActivePendingRound`.
- `discardGame` / `cancelEditRound` — leave the slot without saving.
- `restoreRound(record)` — load a past round into the slot for editing (history
  untouched until re-saved); captures originals for change detection.
- `deleteLastRound` / `rollbackLastRound` — drop the most recent round.
- `setPlayersAndDealer` / `setDealer` / `setPlayerName` — player + dealer edits.
- `setStarterVariant` / `setHeartsVariant` — update one field of `ruleVariants`
  (via `RuleVariants.copyWith`) for the current session.
- `buildSession()` — snapshot state → `GameSession` (or `null` if no session id).
- `reset()` — clear the in-game slot (called after the active session is deleted,
  so the provider returns to the "no active game" idle state).

The shared private `_exitSlot` recomputes `dealerId`/`roundNumber`/`chooserId`
from `firstDealerId` + the *new* history length, so dealer rotation stays correct
whether you appended, replaced, deleted, or cancelled.

**Autosave.** `set state` is overridden to schedule a **400 ms debounced** write
(coalescing keystroke bursts into one SharedPreferences encode). `_autosave`
calls `buildSession()` → `gameHistoryProvider.saveGame()`. Switching to a
different session first **flushes** any pending autosave for the outgoing one.
Autosave is a no-op while `sessionId` is empty. The timer is cancelled in
`ref.onDispose`.

### `gameHistoryProvider` — persistence & suggestions
`AsyncNotifierProvider<GameHistoryNotifier, List<GameSession>>`. Loads + sorts
saved sessions (newest `updatedAt` first); `saveGame` (upsert by id) /
`deleteGame` / `clearHistory`; and `playerNameSuggestions` — unique names across
all sessions ranked by frequency (ties alphabetical, case-insensitive), cached
and invalidated on mutation. See §9 for storage details.

### `themeModeProvider` — theme
`NotifierProvider<ThemeModeNotifier, ThemeMode>`. The persisted value is
**pre-loaded in `main()`** via `loadPersistedThemeMode()` and injected as a
provider override, so the first frame already paints in the chosen theme (no
flash). `setMode` writes through to `SharedPreferences`.

---

## 8. Key flows

End-to-end journeys, naming the methods that fire (great for tracing a change):

- **New game.** Home → "Nieuw spel" → `NewGameScreen` (holds its *own* local
  working state; the provider is untouched until confirmed) → enter names
  (autocomplete from `playerNameSuggestions`) + first dealer (manual or random)
  → "Start spel" → `startNewGame` → push `GameScreen`.
- **Play a round.** `GameScreen` game tile → `selectGame` → push
  `RoundInputScreen` → adjust chooser (`setChooser`), doubles (`updateDoubles`),
  result (`updateInput`); a live/partial score renders as you go → "Opslaan" →
  `deselectGame` appends the round → pop → autosave persists.
- **Resume after restart.** App launches at Home → tap a session card →
  `loadSession` → `GameScreen`. A `pendingRound` shows as an hourglass tile and
  **blocks other games** until it's finished or discarded.
- **Edit a past round.** History row "Wijzigen" → `restoreRound` →
  `RoundInputScreen` in editing mode → "Opslaan" replaces the round; Back /
  "Verwerpen" → `cancelEditRound` (with a confirm if `hasActiveChanges`). Editing
  the *last* round with incomplete input can `rollbackLastRound` (delete it).
- **Delete a game + undo.** Home card delete icon (or `GameScreen` "Spel
  verwijderen" → confirm → navigate Home) → `deleteGame` → a snackbar "Spel
  verwijderd" with "Ongedaan maken" whose action re-`saveGame`s the captured
  session. (`showGameDeletedSnackBar` also has a belt-and-suspenders timer; tests
  must drain it.)
- **Edit a game mid-play.** `GameScreen` → "Spel bewerken" → `EditGameScreen`
  → rename + drag-reorder + change first dealer → `setPlayersAndDealer` applies
  atomically, keeping UUIDs bound to their (new) seats.
- **Theme.** Any app bar `ThemeMenuButton` → `setMode` → persisted immediately.
- **Settings.** `HomeScreen` → `SettingsIconButton` → `SettingsScreen`; pick
  `StarterVariant` / `HeartsVariant` → `setValue` on the relevant
  `EnumPreferenceNotifier` → persisted to `SharedPreferences` immediately.
  Both variants are also per-session: `NewGameScreen` seeds from the defaults on
  open, `EditGameScreen` allows changing them mid-game. Opening rules from
  within a game (`TitleWithRules` → `RulesIconButton`) wraps the pushed
  `RulesScreen` in a `ProviderScope` that overrides the default-variant
  providers with the session values and sets `rulesLockedProvider` → true, so
  only the active rule is shown (no settings icon, no "Spelregel variant"
  alternative). The standalone rules page (home / deep link) leaves both
  unset, so it shows the app defaults plus the alternative and the icon.

---

## 9. Persistence & migration

Backend: `SharedPreferences` ([`game_history_provider.dart`](lib/state/game_history_provider.dart)).

- **Current key:** `game_history`. **Legacy key:** `bonken_game_history`.
- **Envelope (`currentStorageVersion` = 6):** `{ "version": 6, "games": [ … ] }`.
- `GameSession.toJson`: `id`, `createdAt`/`updatedAt` (ISO-8601),
  `players:[{id,name}]`, `firstDealerId`,
  `ruleVariants:{starterVariant, heartsVariant}` (enum names), `rounds:[…]`,
  `pendingRound?`.
- `RoundRecord.toJson`: `roundNumber`, `gameName`, `gameId`, `chooserId`,
  `scores:{playerId:int}`, `input` (the **uniform** `{"counts":[ {uuid:int}, … ]}`
  form, regardless of game shape — see below), `doublesJson?` (omitted unless a
  double exists).
- **`input` shape (v3, all games):** `{"counts": [ {uuid:int}, … ]}` — a
  positional list of per-player count maps. Counts games and single-slot
  recipient games store one element; two-slot recipient games (7e/13e) store two
  (index 0 = 7th, 1 = 13th, so the distinction is preserved). Scoring sums
  element-wise. The game's `inputToCounts` / `countsToInput` convert to/from
  the descriptor-shaped in-memory input (§5).
- `DoubleMatrix.toJson`: flat object — `{"uuidA,uuidB": {"state": …, "initiator": …}, …}`
  (omitted entirely when `!hasAnyDouble`).

**Worked storage example** (one finished-style round + a pending round; UUIDs
shortened, scores match the Vrouwen example in the rules — A wins 3 queens, B
wins 1, B doubled A):

```jsonc
{
  "version": 6,
  "games": [{
    "id": "1716200000000000",
    "createdAt": "2026-05-20T19:30:00.000",
    "updatedAt": "2026-05-20T20:05:00.000",
    "players": [
      {"id": "a1", "name": "Alice"}, {"id": "b2", "name": "Bob"},
      {"id": "c3", "name": "Carol"}, {"id": "d4", "name": "Dan"}
    ],
    "firstDealerId": "a1",
    "ruleVariants": {
      "starterVariant": "dealerStarts",
      "heartsVariant": "onlyAfterPlayedHeart"
    },
    "rounds": [{
      "roundNumber": 1,
      "gameName": "Vrouwen", "gameId": "queens",
      "chooserId": "b2",
      "scores": {"a1": -225, "b2": 45, "c3": 0, "d4": 0},
      // uniform counts list; Queens is a counts game → one element
      "input": {"counts": [{"a1": 3, "b2": 1, "c3": 0, "d4": 0}]},
      // flat pair-object format: key = canonical "smaller,larger" UUID pair
      "doublesJson": {
        "a1,b2": {"state": "doubled", "initiator": "b2"}
      }
    }],
    "pendingRound": {
      "gameId": "duck", "gameName": "Bukken", "chooserId": "c3",
      "input": {"counts": [{"a1": 4, "b2": 0, "c3": 0, "d4": 0}]}
    }
  }]
}
```

**Load behavior (`build`):**
- Missing current key → check/migrate the legacy key (implicitly v1); else `[]`.
- Unreadable storage → throw `CorruptStorageException`, surfaced by the
  `_StorageErrorScreen` ("Geschiedenis beschadigd" + "Geschiedenis wissen"
  button). Deliberately *not* silently `[]` — that would overwrite the user's
  saved games on the next write.
- `version > currentStorageVersion` → throw `UnsupportedStorageVersionException`,
  also surfaced by `_StorageErrorScreen` ("App bijwerken vereist" variant);
  Riverpod schedules a ~200 ms retry, which tests must drain.
- `version < currentStorageVersion` → run `runStorageMigrations(...)`, then
  rewrite the upgraded games under `game_history` at the current version.

**Migration framework ([`migrations.dart`](lib/state/migrations.dart)).**
Migrations are **frozen, sequenced, self-contained** steps. A `StorageMigration`
declares its `fromVersion` and an `apply(games)`; a `const` registry lists the
steps in order; `runStorageMigrations(games, fromVersion:)` applies every step
from the stored version up to `currentStorageVersion`. Each step carries its own
historical key/shape knowledge and **never reads live game code** (descriptors,
classes), so old steps keep working as the models evolve.

- **`_V1ToV2`** — v1 was seat-index-keyed with no player UUIDs. Mints a UUID per
  seat, back-computes `firstDealerId` from the last known dealer, and rewrites
  scores / input / doubles from index-keyed to UUID-keyed (keeping the old
  per-game input keys).
- **`_V2ToV3`** — collapses each round's per-game input (`{tricks|cards: {…}}`,
  `{winner|loser: id}`, `{trick7winner, trick13winner}`) into the uniform
  `{"counts": [ {uuid:int}, … ]}` shape.
- **`_V3ToV4`** — reshapes `doublesJson` from two parallel sub-maps
  (`{pairs:{…}, initiators:{…}}`) into a flat object where each canonical pair
  key maps to a single `{"state": …, "initiator": …}` record.
- **`_V4ToV5`** — adds `starterVariant: 'dealerStarts'` and
  `heartsVariant: 'onlyAfterPlayedHeart'` to every game, materialising the two
  new per-session rule fields introduced in the v5 schema.
- **`_V5ToV6`** — moves the two top-level `starterVariant` / `heartsVariant`
  keys into a single nested `ruleVariants` object, so the persisted shape mirrors
  the `RuleVariants` value class and future rule variants stay grouped.

**When you change a stored shape: append one new `StorageMigration` step, add it
to the registry, and bump `currentStorageVersion` — never edit an existing step
(they are historical) and never silently break old saves.**

---

## 10. UI layer

**Routing (`main.dart`).** `onGenerateRoute` + `onGenerateInitialRoutes` keep
`HomeScreen` at the bottom of the stack. Deep links: `/spelregels` → full rules;
`/spelregels/<gameId>` → that game's rules (so Back returns to Home rather than
leaving the app). Locale is forced to Dutch (`nl`); all three Global*Localizations
delegates are registered.

**Screens** (what they watch / do):
- **`HomeScreen`** — watches `gameHistoryProvider`; renders the saved-games list
  (`ScoreboardCard` per game), the "Nieuw spel" button, theme menu, rules/about.
  Handles resume (tap), delete + undo snackbar, and the storage-error screen
  (unsupported version or corrupt data — see §9).
- **`NewGameScreen`** — local working state only; seeds `StarterVariant` /
  `HeartsVariant` from the default providers; commits via `startNewGame`.
- **`SettingsScreen`** — app-wide default `StarterVariant` + `HeartsVariant`
  (`RadioListTile` per value with label + description); changes persist immediately.
- **`GameScreen`** — the in-game hub. `_GameSelectionBody` separates unplayed
  and played games per category (negative / positive); played games are hidden by
  default and can be revealed via a per-category toggle in `_SectionHeader` —
  when visible they render disabled ("Spel al gespeeld") and offer force-replay
  on tap. Per-chooser quota disabling and pending-round blocking remain as soft
  disables. Also contains `_LiveScoreboard`, a round-history list, and
  edit-game / delete-game actions.
- **`RoundInputScreen`** — composed of focused `ConsumerWidget` cards
  (`_ChooserSelectorCard`, `_DoublesCard`, `_InputFormCard`,
  `_ScoreResultSection`), each declaring its own narrow `select`. Game-specific
  amber warnings are pulled from the rules `Note` blocks. A `PopScope` intercepts
  Back to run discard/save confirmations; the app bar offers "Verwerpen" and
  "Opslaan".
- **`EditGameScreen`** — atomic rename + drag-reorder + first-dealer change
  via `setPlayersAndDealer`; also allows changing `StarterVariant` /
  `HeartsVariant` for the current session.
- **`RulesScreen`** — renders `game_rules.dart` content (full or single game).
  Variant-sensitive blocks read the default-variant providers and
  `rulesLockedProvider`; when locked (the in-game scope set up by
  `RulesIconButton`'s `ProviderScope`), they show only the active text and
  suppress the settings icon + "Spelregel variant" alternative note.

**The doubles picker** (`doubles_picker.dart`) deserves special note — it is the
most intricate widget. Two stacked panels: an **initiator** list (the 4 players
in doubling turn order; tap to select who is acting) and a **target** list (cycle
each other player `none → doubled → redoubled → none`). It enforces the rules
from §6: the chooser can't initiate, redoubling requires your turn not to have
passed (turn-index comparison), and bulk buttons implement *Zaal* / *Slappe hap*
(and, for the chooser, "Terug op beide" / "Zaal terug" bulk-redoubles). Direction
labels ("dubbelt", "gaat terug", "is gedubbeld door") come from the pair state +
initiator. It emits a new `DoubleMatrix` via `onChanged` → `updateDoubles`.

**Theming.** `ThemeExtension`s in `app_theme_extensions.dart` supply
warning / suit / double-state / score-sign colors for both brightnesses;
`utils.dart`'s `scoreColor` reads them (with a brightness fallback for unthemed
test widgets). `GameAvatar` + `_GameSymbol` render a game's `GameSymbol`.

---

## 11. Testing strategy

Tests are a first-class part of this codebase: keep the suite green, keep it
**current with the code** (update or add tests in the same change), and aim for
**good coverage** of new behavior — especially the scoring engine, state
transitions, and persistence/migration, where regressions are silent and costly.
Run with `flutter test`. Layout mirrors `lib/`:

- **`test/models/`** — pure domain: scoring (`scoring_test`,
  `scoring_doubles_test`), `double_matrix_test`, `game_session_test`,
  `mini_game_test` (incl. the input↔counts storage converters),
  `game_mechanics_test` (dealer rotation + per-chooser quota), `score_result_test`.
- **`test/state/`** — `calculator_provider_test`, `game_history_provider_test`
  (incl. migration, corrupt data, and unsupported-version handling).
- **`test/widgets/`** — one file per screen/widget.
- **Guards:** `architecture_test.dart` fails the build if any screen uses raw
  `Scaffold` instead of `AppScaffold`, or if any file calls
  `showModalBottomSheet` directly instead of `showAppBottomSheet`;
  `license_assets_test.dart` verifies the bundled-license registration from
  `main.dart`; `a11y_test.dart` pumps every
  screen and gates `textContrastGuideline`, `labeledTapTargetGuideline`, and
  `android`/`iOSTapTargetGuideline` (see §2 for the full a11y posture).

**Shared helpers** ([`test/test_helpers.dart`](test/test_helpers.dart)):
`setUpPrefs()` resets mock `SharedPreferences` per test; `initializeWidgets()`
ensures the binding.

**Conventions to know:**
- Seed prefs with `SharedPreferences.setMockInitialValues({...})`.
- The **autosave debounce** (400 ms), the **snackbar** auto-dismiss timer, and
  the **Riverpod retry** (~200 ms) all leave pending timers that must be
  **drained** (`await tester.pump(Duration(...))` / `pumpAndSettle`) or teardown
  fails. See `game_screen_actions_test.dart` and the `drainRetry` helper in
  `game_history_provider_test.dart`.
- `showGameDeletedSnackBar` (via `showTimedSnackBar` internally) cancels any
  prior pending close-`Timer` on a back-to-back call; a test that triggers two
  deletes in sequence need only drain the **one** remaining timer. When testing
  the undo action, invoke `SnackBarAction.onPressed` directly rather than
  tapping the widget — tapping calls `hideCurrentSnackBar` which, combined with
  the belt-and-suspenders `controller.close` timer, throws
  `Bad state: No element` on the second close.
- Construct fixtures with real model objects (e.g. `const Dominoes()`,
  `RoundRecord(...)`), not hand-rolled JSON, so they stay in sync with the code.

---

## 12. Build, run & release

Flutter SDK version is pinned in [`.fvmrc`](.fvmrc). CI installs it
from there via the `setup-build` action; bare `flutter` / `dart` work locally,
and `fvm flutter <cmd>` runs against the pinned version exactly. Bump the pin to
the latest **stable** release with `dart run tool/update_flutter.dart`
([`--check`](tool/update_flutter.dart) reports without writing) — it rewrites
`.fvmrc` and the `pubspec.yaml` Dart `sdk:` lower-bound together, never
downgrades, and prints the follow-up steps (install the SDK, re-resolve, run the
gates).

```bash
flutter pub get
flutter run                                       # Android device / emulator
flutter run -d chrome                             # Web
flutter test                                      # All tests
flutter analyze                                   # Static analysis (lints from analysis_options.yaml)
dart format .                                      # Auto-format all Dart (run before committing)
dart format --output=none --set-exit-if-changed . # Formatting check (what CI runs; exits 1 on drift)

flutter build apk --release                       # Android APK
flutter build web --release --base-href /bonken/  # Web (GitHub Pages)
```

- **CI verification gates.** The
  [`verify`](.github/actions/verify/action.yml) composite action (run by the
  `develop` and `release` workflows) enforces **three** gates, in order:
  `dart format --output=none --set-exit-if-changed .`, `flutter analyze
  --fatal-infos`, and `flutter test`. Run all three locally before pushing.
  **Coding agents:** `flutter analyze` and `flutter test` are not enough — also
  run `dart format .` (formatting drift fails CI just like an analyzer error).
- **The analyzer is intentionally strict** ([`analysis_options.yaml`](analysis_options.yaml)):
  `strict-casts` / `strict-inference` / `strict-raw-types` plus
  `require_trailing_commas`, `always_declare_return_types`,
  `avoid_dynamic_calls`, `avoid_type_to_string`, and `unawaited_futures`. On top
  of those, a set of *preventive* lints: const correctness
  (`prefer_const_constructors` / `_declarations` / `_literals_to_create_immutables`),
  `prefer_final_locals`, `directives_ordering`, `discarded_futures`,
  `avoid_catches_without_on_clauses` (every `catch` must declare `on …`), plus
  `unnecessary_parenthesis` / `_lambdas` / `_breaks`, `avoid_redundant_argument_values`,
  `combinators_ordering`, and `sized_box_shrink_expand`. Write explicit types,
  declare return types, wrap fire-and-forget futures in `unawaited(...)`, and
  let `dart format` add the trailing commas.
- **`dart fix --dry-run` is part of `verify`** — CI fails if the analyzer
  proposes any auto-fix. Run `dart fix --apply` locally to clear drift before
  pushing.
- **Versioning:** `pubspec.yaml` is a sentinel `0.0.0+0`; CI passes
  `--build-name` / `--build-number` from the git tag / run number.
- **Fonts:** Roboto + DejaVu Sans are bundled under versioned asset paths with
  runtime fetching disabled (offline + deterministic suit glyphs). Upgrade via
  `tool/update_fonts.sh` (bumps the version, asset paths, and `.ttf`s atomically).
- **Launcher icons:** `./tool/generate_icons.sh` — renders the SVG sources to
  PNGs, runs `flutter_launcher_icons` (config in `pubspec.yaml`), then overwrites
  the PWA maskable icons with `icon_bonken_maskable.svg`. Do not run
  `dart run flutter_launcher_icons` directly: it produces incorrect PWA maskable
  icons (no safe-zone padding) and skips the intermediate 1024 px PNGs.
  **Safe-zone calibration:** `icon_bonken_maskable.svg` and
  `icon_bonken_adaptive_fg.svg` both use viewBox `−128 −128 1280 1280` (card at
  50 % of canvas). The native `android:inset="10%"` (`adaptive_icon_foreground_inset`
  in `pubspec.yaml`) shrinks the foreground to 80 % of the 108 dp canvas, so
  adaptive corners are ~8–10 px inside the 36 dp safe zone (at 3–4× DPI). The
  PWA maskable corners are ~7 px inside the 40 %×1280 = 512 SVG-unit safe zone
  on the 512 px icon file. If `adaptive_icon_foreground_inset` or the card
  geometry changes, recalculate both margins.
  **Why the card isn't larger (do not "fix" the visible gap):** the card corner
  reaches 1.545× its half-width (rounded-rect geometry), so at the current sizing
  it already sits at ~93 % (adaptive 36 dp safe zone) / ~96.6 % (maskable 40 %
  radius) of the *circle* safe-zone edge — i.e. near the maximum that guarantees
  no corner-clipping under a **circle** mask. On generous masks (Samsung/OneUI &
  Apple squircles, MIUI rounded-square) the card looks small with a visible gap to
  the edge, because a squircle bulges past the inscribed circle the card is sized
  for. That gap is intrinsic: closing it (enlarging the card) pushes the corners
  outside the circle and clips them for every **circle-shape** user — stock
  Android/Pixel default, and Samsung/OneUI when the user selects the circle icon
  shape. The exact circle-safe maxima are inset 6.9 % / viewBox 1236 (only ~9 % /
  ~3.6 % bigger — marginal), so the gap cannot be meaningfully reduced without
  sacrificing the no-clip guarantee. This was a deliberate decision; keep it.
  (**iOS is not bound by this** — iOS only rounds the corners, no circle mask, so
  its full-bleed icon is sized fuller: `image_path_ios` points at `icon_bonken.png`
  (`icon_bonken.svg`, 62.5 % card) — the same source the PWA `apple-touch-icon`
  uses — so the iOS-native and iOS-PWA icons render at the same size. At 62.5 % the
  card still clears the iOS corner squircle. iOS rejects alpha, so `remove_alpha_ios`
  flattens onto `background_color_ios` (`#283593`); the source is already opaque.
  Generating the iOS `AppIcon.appiconset` (the `flutter_launcher_icons` iOS pass)
  needs the `ios/` Runner project present and runs only on macOS/Xcode.)
- **Updates:** `services/app_updater.dart` checks Google Play for a newer build
  (Android only; no-op on web/iOS/sideloaded; never blocks startup).

---

## 13. Conventions & invariants (quick reference)

Things to *not* break:

- **Always 4 players, 12 rounds** (`playerCount`, `GameSession.totalRounds`).
- **Key everything by player UUID**, never seat index; derive indices on demand.
- **Σ scores == `totalPoints`** for every game — the engine invariant (asserted).
- **Seat-relationship math lives only in `game_mechanics.dart`** — don't
  re-derive "dealer = chooser − 1" or "starter = …" elsewhere. This includes
  `starterIndexFor`, which takes a `StarterVariant` and lives here.
- **Screens use `AppScaffold`** (architecture test enforces it).
- **Bottom sheets use `showAppBottomSheet`**, never `showModalBottomSheet`
  directly (architecture test enforces it).
- **Icons are `Symbols.*` only** — never the legacy `Icons`.
- **Empty-string IDs are the "not yet set" sentinel** — don't assert player
  lookups on them (`_indexOf` already guards this).
- **Derived lists watched by `select()` must keep stable identity** — store them
  as fields, recompute in `copyWith` only when inputs change.
- **`pending` is sealed** — branch with `is ActivePendingRound`; never resurrect
  the old "three nullable fields" pattern.
- **Section and card titles use `Semantics(header: true)`** — `FormSectionCard`
  does this automatically; hand-written cards must add it explicitly.
- **Append a `StorageMigration` step + bump `currentStorageVersion`** when
  changing stored JSON shape (never edit an existing, frozen step).
- **UI strings in Dutch, code identifiers in English.**
- **Run `dart format` before committing** — CI's `verify` action fails on
  unformatted Dart (`dart format --output=none --set-exit-if-changed .`).
- **Update CLAUDE.md / ARCHITECTURE.md as part of the change** when it affects
  documented architecture, conventions, the storage version, the directory map,
  or invariants — not as a follow-up.

---

## 14. Glossary (Dutch → English)

**Core terms:**

| Dutch | English / meaning |
|-------|-------------------|
| deler | dealer (plays the first card; `dealerIndexFor`) |
| kiezer | chooser — the player who picks the round's mini-game |
| ronde | round (12 per game) |
| spelvorm | mini-game / game variant |
| slag | trick |
| troef | trump |
| strafkaart / strafslag | penalty card / penalty trick (negative games) |
| dubbelen | doubling |
| teruggaan / "gaat terug" | redoubling (count the difference twice) |
| Zaal | doubling all three other players |
| Slappe hap / Ruitenwisser | doubling exactly the two non-chooser players |
| "is gedubbeld door" | "is doubled by" (target-side label) |
| tussenstand / eindstand | running (current) score / final score |
| spelregels | rules |
| Nieuw spel / Start spel | New game / Start game |
| Opslaan / Verwerpen | Save / Discard |
| Ongedaan maken | Undo |
| Spel bewerken / Spel verwijderen | Edit game / Delete game |

**Mini-game names** (ids in §5): Klaveren=Clubs, Ruiten=Diamonds, Harten=Hearts,
Schoppen=Spades, Zonder troef=No Trump, Harten Heer=King of Hearts,
Heren/Boeren=Kings/Jacks, Vrouwen=Queens, Bukken=Duck, Harten punten=Heart
points, 7e/13e=7th/13th trick, Laatste slag=Final trick, Domino=Dominoes.
