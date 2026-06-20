# Bonken — Architecture & Design Specification

> Authoritative deep reference for developers and coding agents: how the code is
> built and why.
>
> - **Day-to-day quick-start** (commands, CI gates, conventions, finish checklist):
>   [`AGENTS.md`](AGENTS.md) — auto-loaded by coding agents; points here for detail.
> - **Player-facing docs** (Dutch — install, rules): [`README.md`](README.md).
> - **In-app rules text**: [`lib/data/game_rules.dart`](lib/data/game_rules.dart).

**Contents**

1. [Overview](#1-overview)
2. [Design philosophy](#2-design-philosophy)
3. [Architecture at a glance](#3-architecture-at-a-glance)
4. [Directory map (`lib/`)](#4-directory-map-lib)
5. [Domain model](#5-domain-model) — [`MiniGame`](#minigame--shape-bases-mini_gamedart) · [`GameInput`+`InputDescriptor`](#gameinput--inputdescriptor-input_descriptordart) · [`Player`](#player-playerdart) · [`DoubleMatrix`](#doublematrix-double_matrixdart) · [`ScoreResult`](#scoreresult-score_resultdart) · [`RoundRecord`](#roundrecord-round_recorddart) · [`GameSession`](#gamesession--pendinground-game_sessiondart) · [`game_mechanics`](#game_mechanicsdart-game_mechanicsdart)
6. [Scoring & doubling](#6-scoring--doubling-deep-dive) — [Engine](#the-engine) · [Worked example](#worked-example-harten-20trick) · [Doubling representation](#how-doubling-is-represented--enforced)
7. [State management](#7-state-management) — [`calculatorProvider`](#calculatorprovider--the-in-game-state-machine) · [`gameHistoryProvider`](#gamehistoryprovider--persistence--suggestions) · [`themeModeProvider`](#thememodeprovider--theme)
8. [Key flows](#8-key-flows)
9. [Persistence & migration](#9-persistence--migration) — [Settings](#settings-persistence-settings_storagedart) · [Backup / export-import](#backup--export-import-export_import_notifierdart)
10. [UI layer](#10-ui-layer)
11. [Testing strategy](#11-testing-strategy)
12. [Build, run & release](#12-build-run--release) — [Commands](#common-commands) · [CI gates](#ci-quality-gates) · [Versioning](#versioning--release) · [GHA & runners](#github-actions--runners) · [Fonts](#fonts) · [Icons & splash](#launcher-icons--splash-screens) · [Screenshots](#store-screenshots) · [Dependency updates](#dependency-updates) · [Update check](#app-update-check)
13. [Deferred upgrades](#13-deferred-upgrades) — [`builtInKotlin`](#androidbuiltinkotlintrue-agp-9-built-in-kotlin) · [`newDsl`](#androidnewdsltrue-agp-9-new-gradle-dsl) · [`file_picker`](#file_picker-stable-12x-currently-pinned-to-a-beta)
14. [Conventions & invariants](#14-conventions--invariants-quick-reference)
15. [Glossary](#15-glossary-dutch--english)

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
  Android/iOS/desktop) and as native **Android** (APK/AAB on Google Play) and
  **iOS/iPadOS** (universal app on the App Store / TestFlight) builds.
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
  release). e.g. `_recalculate` asserts the score sum equals `totalPoints`. Bugs
  crash loudly in dev, degrade quietly in prod.
  Player-id lookups (`seatIndexOf`, `gameById`) are an exception: they throw
  always, because an unknown id after storage load is either corruption (caught at
  the load boundary and surfaced as `CorruptStorageException`) or a programming
  bug — neither should silently substitute a wrong player/game.

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

- **Screens are guarded.** Every full-screen route uses `AppScaffold` (wraps
  the body in `SafeArea` for edge-to-edge mode; also wraps it in a
  `GestureDetector(onTap: () {})` tap absorber so that tapping a rendered
  non-interactive element — `Card`, `Text` — cannot produce tiny scroll deltas
  that activate the AppBar's M3 scrolled-under elevation tint). Enforced by a
  test — [`test/architecture_test.dart`](test/architecture_test.dart).

- **Bottom sheets are guarded.** All modal bottom sheets call
  `showAppBottomSheet` (wraps content in a `Padding` sized to
  `MediaQuery.viewPaddingOf.bottom`, clearing the system navigation bar;
  always enables `isScrollControlled` and `useSafeArea`). Direct calls to
  `showModalBottomSheet` are forbidden and caught by the same test in
  [`test/architecture_test.dart`](test/architecture_test.dart).

- **Primary form actions look disabled but stay tappable.** Save/start buttons
  pass `onPressed: null` (truly disabled — native M3 colours, WCAG-exempt) when
  the form is incomplete or invalid. A transparent `GestureDetector` overlay
  (`ExcludeSemantics`, `HitTestBehavior.opaque`) sits on top and calls
  `showIncompleteFormSnackBar` with a specific reason when tapped — the user
  sees the form is not ready *and* learns why when they tap anyway.
  `incomplete_form_snackbar.dart` is the shared helper; `DisabledTapDetector`
  (`lib/widgets/disabled_tap_detector.dart`) is the shared Stack+overlay widget.

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
            ┌───────────────────────────────────────────────┐
  UI        │  lib/screens/*  +  lib/widgets/*              │  ConsumerWidgets
            │  watch providers · call notifier methods      │
            └───────────────┬───────────────────────────────┘
                            │ ref.watch(provider.select) / ref.read(...notifier)
            ┌───────────────▼───────────────────────────────┐
  STATE     │  lib/state/*  (Riverpod Notifiers)            │
            │  calculatorProvider · gameHistoryProvider ·   │
            │  themeModeProvider                            │
            └───────────────┬───────────────────────────────┘
                            │ construct/read models · toJson/fromJson
            ┌───────────────▼───────────────────────────────┐
  MODELS    │  lib/models/*  (pure Dart, no UI)             │
            │  MiniGame scoring engine · session · doubles  │
            └───────────────────────────────────────────────┘
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
                             bundled-font license registration (Arimo SIL OFL via
                             registerBundledLicenses()), edge-to-edge, Android update check.
  utils.dart                 Cross-cutting helpers: formatDate/formatScore, scoreColor,
                             disabledOnSurface, reorder index math, shared string constants.

  models/                    Pure domain layer (no Riverpod; minimal Flutter).
    mini_game.dart           MiniGame abstract base + calculateScores engine; GameSymbol
                             sealed union; GameCategory; playerCount(4); doublingTurnIndex.
    game_mechanics.dart      dealerIndexFor / starterIndexFor — ONLY home of seat relationships.
    game_constraints.dart    Single source of truth for valid game data: kPlayerNameMaxLength /
                             kGameNameMaxLength + predicate/normalizer functions (name trim,
                             length, case-insensitive uniqueness). Composed by game_invariants,
                             validation.dart, and the create/edit UI alike. Pure Dart, no Flutter.
    game_invariants.dart     GameInvariantError + assertGameInvariants(GameSession): models-layer
                             checks (4 players, no dup ids/names, rounds ≤ 12, Σ scores invariant,
                             mini-game-specific input checks). Used by the import validation path.
    input_descriptor.dart    Sealed GameInput (CountsInput/RecipientInput) + sealed InputDescriptor.
    player.dart              Player (stable UUID id + name).
    double_matrix.dart       DoubleMatrix: per-pair doubling state + initiator, UUID-keyed.
    score_result.dart        ScoreResult: {playerId: pointsThisRound}.
    round_record.dart        RoundRecord: one completed round (in-memory + toJson).
    game_session.dart        GameSession aggregate + PendingRound; derived totals/winners; JSON;
                             _validateReferences (id referential-integrity check at load boundary).
    rule_variants.dart       RuleVariants: per-game StarterVariant + HeartsVariant, grouped + JSON.
    games/
      game_catalog.dart      allGames — the single ordered list of all 13 mini-games; gameById()
                             — the single lookup helper (throws on unknown id).
      positive_games.dart    PositiveGame base + Clubs/Diamonds/Hearts/Spades/NoTrump.
      negative_games.dart    The 8 negative mini-games.

  state/                     Riverpod providers.
    calculator_provider.dart CalculatorState (sealed: NoSession | ActiveSession) +
                             CalculatorNotifier (the in-game state machine);
                             activeSessionProvider narrows it to ActiveSession.
    game_history_provider.dart Persistence (SharedPreferences) + versioning; runs migrations on load.
                             Also owns replaceAll(List<GameSession>) used by the import path.
    migrations.dart          Sequenced, frozen StorageMigration steps (v1→…→v10) + runner. currentStorageVersion = 10.
    settings_storage.dart    Versioned `settings` blob: load, write, bootstrap from legacy keys,
                             error types (UnsupportedSettingsVersionException / CorruptSettingsException),
                             settingsLoadErrorProvider.
    settings_migrations.dart Sequenced, frozen SettingsMigration steps + runner (mirrors migrations.dart).
    storage_exceptions.dart  HasCause interface shared by CorruptStorageException + CorruptSettingsException.
    theme_mode_provider.dart Light/dark/system theme, persisted via settings blob; pre-loaded in main().
    default_starter_variant_provider.dart  App-wide default StarterVariant; persisted via settings blob; pre-loaded in main().
    default_hearts_variant_provider.dart   App-wide default HeartsVariant; persisted via settings blob; pre-loaded in main().
    enum_preference_notifier.dart  Generic EnumPreferenceNotifier<T> base (settingsKey + settingsSection).
    rules_edit_mode_provider.dart  RulesEditMode enum (default enabled); controls cog-icon behaviour
                             in variant-sensitive rule blocks. Overridden by RulesIconButton for
                             the pushed route: hidden (score input — hides cog), disabled
                             (game screen — cog shown but shows a snackbar directing to Spel bewerken).
    backup_migrations.dart   BackupData typedef + BackupMigration abstract class + backupMigrations
                             registry (currently empty) + currentBackupVersion (1). Append here
                             when the ZIP envelope structure changes.
    export_import_notifier.dart  exportBackup() top-level function + ImportAnalysis + analyzeBackup()
                             (read-only analyze pass) + ImportResult + ImportNotifier (applyImport —
                             all-or-nothing commit). See §9 "Backup / export-import".
    validation.dart          ValidationError + validateManifest / validateMigratedGames /
                             validateMigratedSettings — state-layer gate between raw JSON and
                             live providers. Catches GameInvariantError from the models layer.

  screens/                   Full-screen routes (all use AppScaffold).
    home_screen.dart         Start: saved-games list, "Nieuw spel", theme menu; resume/delete+undo.
    new_game_screen.dart     Enter names (with suggestions) + pick first dealer + pick variants.
    game_screen.dart         In-game hub: game selection, live scoreboard, history, edit/delete;
                             share / save / copy the result (image or text) when finished.
    round_input_screen.dart  Per-round: chooser, doubles, input form, live/final result.
    edit_game_screen.dart Rename/reorder players + change first dealer + change variants mid-game.
    rules_screen.dart        Renders rules content (full doc or single game); variant text and
                             whether the alternative is shown come from the variant providers +
                             rulesEditModeProvider (overridden per-route when opened in-game).
    settings_screen.dart     App-wide default settings: StarterVariant + HeartsVariant + Gegevens
                             (export + import entry points).
    import_screen.dart       Full-screen import flow (idle → analyzing → analyzed → applying);
                             uses ImportNotifier.applyImport.
    migration_screen.dart    Terminal "Bonken is verhuisd" screen for the legacy app id
                             (com.suninet.bonken): links to the new Play Store listing and
                             offers a one-off data export. Shown instead of HomeScreen when
                             main()'s isLegacyApp is true (see §8).

  widgets/                   Reusable UI.
    app_scaffold.dart        SafeArea-wrapping Scaffold (mandatory for screens); body wrapped in a
                             tap-absorbing GestureDetector (see §2 "Screens are guarded").
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
                             + subtitle + child); used on new-game, edit-game, settings, import.
    export_screen.dart       Full-screen route for the export flow; scope radio group +
                             "Export delen" (share sheet) and "Export opslaan" (save-to-device).
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
  services/share_service.dart  shareFile() (web/mobile XFile creation) + shareText() — share-sheet
                             helpers with PlatformException handling; used by game_screen (score
                             PNG + text) and export_screen (backup ZIP), via platform_io_providers.
  services/file_pick_service.dart  pickBackupBytes() — picks a .zip via FilePicker, returns bytes;
                             used by import_screen via platform_io_providers.
  services/save_service.dart  saveFile() — saves bytes to device storage without a share sheet
                             (Android SAF picker / iOS Documents / web download), plus the
                             saveZipFile / saveImageFile wrappers. Web download is split out into
                             save_service_io.dart (stub) + save_service_web.dart (package:web)
                             via a conditional import. Used by export_screen (ZIP) + game_screen
                             (result PNG), via platform_io_providers. iOS saves to the app's
                             Documents directory; `UIFileSharingEnabled` +
                             `LSSupportsOpeningDocumentsInPlace` in
                             `ios/Runner/Info.plist` make it visible in Files app
                             (On My iPhone → Bonken).
  state/platform_io_providers.dart  shareFileProvider / shareTextProvider / pickBackupBytesProvider /
                             saveZipFileProvider / saveImageFileProvider — DI seams over the
                             services; overridden in tests (see §11).
```

---

## 5. Domain model

### `MiniGame` + shape bases ([`mini_game.dart`](lib/models/mini_game.dart))
Abstract base for all 13 games (declares `id`, `name`, `symbol`, `category`,
`pointsPerUnit`, `totalPoints`). It supplies the shared **`calculateScores`**
engine (§6) and defines `GameSymbol` (sealed: `TextSymbol` short label,
`SuitSymbol` ♠♥♦♣ in bundled Arimo, `IconSymbol` Material Symbol).

Concrete games never extend `MiniGame` directly — they extend one of **two
intermediate bases, one per input shape** (mirroring the sealed `GameInput` /
`InputDescriptor` hierarchies). Each base owns `rawCounts`, `inputDescriptor`,
and the storage round-trip (`inputToCounts` / `countsToInput`, §9); a leaf game
declares only its metadata + the human-facing bits:

| base | in-memory type | leaf supplies | members |
|------|----------------|---------------|---------|
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
The persisted aggregate: `id` (UUID v4), `createdAt`/`updatedAt`/`scoredAt`, `players`,
`firstDealerId`, `ruleVariants` (a `RuleVariants` grouping the per-game
`starterVariant` + `heartsVariant`), `rounds: List<RoundRecord>`,
optional `pendingRound`, and an optional user-supplied `gameName` (shown on the
scoreboard cards and in the shared result; never the empty string — null when
unset). `scoredAt` records when scores last changed (round appended, replaced,
or deleted); player/name/rule edits leave it unchanged. It is shown on scoreboard
cards and in both share formats. `updatedAt` continues to track any meaningful
save (including player/rule changes).
Lazily-computed (`late final`) derived getters: `isFinished` (≥ `totalRounds`
== 12), `finalScoresByPlayer`, `winnerIds`, and the display-ordered
`displayedPlayers` / `displayedPlayerNames` / `displayedScores` /
`displayedWinnerIndices` (rotated so the round-1 dealer is first). `fromJson`
resolves each round's `gameId` against `allGames`.
**`PendingRound`** is a round started but not yet scored — it stores
`gameId` string + `input` + optional `doublesJson` so partial work
survives an app restart. Its `toJson`/`fromJson` resolve the game by `gameId` to
convert `input` to/from the uniform counts form, same as a round.

### `game_mechanics.dart` ([`game_mechanics.dart`](lib/models/game_mechanics.dart))
`dealerIndexFor(chooserIndex) = (chooserIndex − 1) mod 4` (the dealer sits to the
chooser's right; equivalently the chooser is left of the dealer).
`starterIndexFor(chooserIndex, StarterVariant)` — the seat index of the player
who leads the first trick: `dealerStarts` → same as the dealer; `oppositeChooserStarts`
→ `(chooserIndex − 2) mod 4`. Both seat *relationships* live here so this file
remains the single home for the dealer/chooser/starter formulas. (Plain
`List<Player>` index lookups and display rotations — `seatIndexOf`,
`rotatedFromDealer` — are list utilities, not relationship math, and live with
`Player` in [`player.dart`](lib/models/player.dart).)
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
|---|---:|---:|---:|---:|---:|
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
`NotifierProvider.autoDispose<CalculatorNotifier, CalculatorState>`
([`calculator_provider.dart`](lib/state/calculator_provider.dart)). Holds the
**single game currently being played or edited**.

`CalculatorState` is **sealed**: `NoSession` (initial/idle state) or `ActiveSession`
(carries all the fields below). "No game active" is `state is NoSession`; autosave
is a no-op in that state. The session-bound screens (GameScreen, RoundInputScreen,
EditGameScreen) only ever run with an `ActiveSession`, so they watch the derived
**`activeSessionProvider`** (`Provider.autoDispose<ActiveSession>`) instead of
casting `state as ActiveSession` at every call site — the cast lives once, in that
provider. Both providers are `autoDispose`: when the user returns to Home all
session-bound screens unmount, their subscriptions drop, and the two providers
dispose in sequence (derived first, then `calculatorProvider`). `calculatorProvider`'s
`onDispose` callback flushes any pending debounced autosave before the state
disappears, so no last-second edit is lost. There is no explicit `NoSession`
transition on back-navigation; `NoSession` is simply the initial state the next
time the provider is created.

**`ActiveSession` fields**, grouped:

| group | fields | notes |
|-------|--------|-------|
| identity | `sessionId`, `createdAt`, `updatedAt`, `scoredAt` | always present in `ActiveSession`; `scoredAt` advances only on `_exitSlot(historyChanged: true)` (round append/replace/delete); the idle signal is `NoSession`, not an empty `sessionId` |
| players | `players`, `playerNames`*, `displayedPlayers`* | *stored derived, for `select()` stability |
| seating | `firstDealerId`, `dealerId`, `chooserId` | IDs; seat indices via `dealerIndex`/`chooserIndex`/`firstDealerIndex`/`displayedChooserIndex` getters |
| progress | `roundNumber` (1–12), `history: List<RoundRecord>` | |
| current slot | `selectedGame`, `input`, `doubles`, `result`, `partialResult` | the round being entered |
| stash | `pending: PendingRoundState` | sealed: `NoPendingRound` \| `ActivePendingRound{game,input,doubles}` |
| edit | `editingRoundIndex`, `editOriginal{Input,Doubles,ChooserId}` | non-null while re-editing a past round |
| rules | `ruleVariants: RuleVariants` | per-game `starterVariant` + `heartsVariant`, grouped (mirrors `GameSession`); `starterIndex` getter reads it |
| label | `gameName` | optional user-supplied session name (mirrors `GameSession`); null when unset, never the empty string |

Helper getters: `hasPendingGame`, `hasMeaningfulPendingInput`, `inputState`
(`InputState{none,partial,complete}` via the descriptor), `isEditingExistingRound`,
`isEditingLastRound`, and `hasActiveChanges` (deep-equals
current vs. captured originals; gates discard confirmations).

`result` is the **final** score (input complete). `partialResult` is a **live
preview** shown while a counts game is partway entered (0 < sum < total).
`_recalculate` switches on `inputState`: complete → set `result`; partial → set
`partialResult`; none → clear both. It skips emitting when the value is unchanged.

**Notifier methods (the transitions):**
- `startNewGame({players, dealerIndex, ruleVariants, gameName})` — fresh session
  id + reset.
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
- `deleteLastRound` — drop the most recent completed round (dealer/round roll back).
- `exitPendingSlot` — leave the live slot *without* saving or discarding the
  pending round (Back with meaningful input on a pending round); the stash is
  already kept current by write-through in `updateInput`/`updateDoubles`.
- `setPlayersAndDealer` / `setDealer` / `setPlayerName` — player + dealer edits.
- `setStarterVariant` / `setHeartsVariant` — update one field of `ruleVariants`
  (via `RuleVariants.copyWith`) for the current session.
- `setGameName(name)` — set or clear the session's optional `gameName` (pass null
  to clear).
- `buildSession()` — snapshot state → `GameSession` (or `null` if no session id).
- `reset()` — cancel autosave timer and clear to `NoSession` (without saving).
- `cancelPendingAutosave()` — cancel the debounced timer without saving. Called
  before deleting a game so the timer cannot re-save a session that was just
  removed from history.

The shared private `_exitSlot` recomputes `dealerId`/`roundNumber`/`chooserId`
from `firstDealerId` + the *new* history length, so dealer rotation stays correct
whether you appended, replaced, deleted, or cancelled.

**Autosave.** `set state` is overridden to schedule a **400 ms debounced** write
(coalescing keystroke bursts into one SharedPreferences encode). `_autosave`
calls `buildSession()` → `gameHistoryProvider.saveGame()`. Switching to a
different session first **flushes** any pending autosave for the outgoing one.
Autosave is a no-op in `NoSession`. On back-navigation the provider auto-disposes
and `ref.onDispose` fires the flush immediately (cancels the timer, writes
synchronously); for the delete flow, `cancelPendingAutosave` suppresses the timer
before the pop instead.

### `gameHistoryProvider` — persistence & suggestions
`AsyncNotifierProvider<GameHistoryNotifier, List<GameSession>>`. Loads + sorts
saved sessions (newest `scoredAt` first); `saveGame` (upsert by id) /
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
  `loadSession` → `GameScreen`. A `pendingRound` with meaningful input
  (`hasMeaningfulPendingInput`) shows as an hourglass tile and **blocks other
  games** until it's finished or discarded.
- **Edit a past round.** History row "Wijzigen" → `restoreRound` →
  `RoundInputScreen` in editing mode → "Opslaan" replaces the round; "Verwerpen"
  → `cancelEditRound` (with a confirm if `hasActiveChanges`). Back with unsaved
  changes shows a "Scores aangepast" info dialog (save or discard to leave). A
  round started but not yet scored (a *pending* round, not an edit) instead
  uses `exitPendingSlot` on Back when `hasActiveChanges` (stash is kept current
  by write-through); if nothing was entered, Back silently calls `discardGame`
  so fat-fingering a game leaves no trace.
- **Delete a game + undo.** Home card delete icon (or `GameScreen` "Spel
  verwijderen" → confirm → `deleteGame` → `cancelPendingAutosave` → pop →
  provider auto-disposes → `NoSession` on next creation)
  → a snackbar "Spel verwijderd" with "Ongedaan maken" whose action re-`saveGame`s
  the captured session. (`showGameDeletedSnackBar` also has a belt-and-suspenders
  timer; tests must drain it.)
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
  providers with the session values and sets `rulesEditModeProvider`. The
  score input screen uses `hidden` (cog suppressed — variant is fixed for
  the round). The game screen uses `disabled` (cog shown but tapping shows
  a snackbar directing the user to 'Spel bewerken'). The standalone rules page
  (home / deep link) leaves the mode at `enabled`, showing app defaults plus
  the alternative and the picker icon.
- **Legacy-app migration.** The app id moved `com.suninet.bonken` →
  `org.suninet.bonken` (new Play Store listing). When `main()` detects the legacy
  id (`isLegacyApp`), the initial route is `MigrationScreen` instead of
  `HomeScreen` — a terminal "Bonken is verhuisd" screen (`PopScope(canPop:false)`)
  that links to the new listing and offers a one-off data export so the user can
  re-import in the new app. `isLegacyApp` is hardcoded `false` until the new
  listings are live.

---

## 9. Persistence & migration

Backend: `SharedPreferences` ([`game_history_provider.dart`](lib/state/game_history_provider.dart)).

- **Current key:** `game_history`. **Legacy key:** `bonken_game_history`.
- **Envelope (`currentStorageVersion` = 10):** `{ "version": 10, "games": [ … ] }`.
- `GameSession.toJson`: `id`, `createdAt`/`updatedAt`/`scoredAt` (bare local
  ISO-8601, no timezone suffix — e.g. `"2026-05-20T19:30:00.000"`),
  `players:[{id,name}]`, `firstDealerId`,
  `ruleVariants:{starterVariant, heartsVariant}` (enum names), `rounds:[…]`,
  `pendingRound?`, `gameName?` (optional user-supplied label; omitted when null,
  like `pendingRound`). `scoredAt` is always emitted; `fromJson` requires the key
  (guaranteed by the v8→v9 migration).
- `RoundRecord.toJson`: `roundNumber`, `gameId`, `chooserId`,
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
  "version": 10,
  "games": [{
    "id": "1716200000000000",
    "createdAt": "2026-05-20T19:30:00.000",
    "updatedAt": "2026-05-20T20:05:00.000",
    "scoredAt": "2026-05-20T20:05:00.000",
    "gameName": "Kerst 2024",
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
      "gameId": "queens",
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
      "gameId": "duck", "chooserId": "c3",
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
- **`_V6ToV7`** — normalises JS negative-zero in persisted round scores. On
  dart2js, `0 × negative` produced `-0` which could survive serialisation as
  `-0.0` (a double) rather than `0` (an int), violating the intended `int` type
  of scores. The source bug is fixed in `MiniGame.calculateScores`; this step
  repairs data written before that fix.
- **`_V7ToV8`** — introduces the optional `gameName`. A **no-op** data step
  (`apply` returns the games unchanged): `gameName` is serialised only when set
  (omit-when-null), so a v7 game — which never had a name — is already a valid v8
  game with no name. The bump exists only as a version gate, so an older v7-only
  build refuses a v8 file (`version > currentStorageVersion` → "App bijwerken
  vereist") instead of silently dropping a name a newer build wrote.
- **`_V8ToV9`** — adds `scoredAt` to every game by copying `updatedAt`. This is
  the best available approximation: prior builds did not record when scores
  specifically changed, only when any meaningful save occurred.
- **`_V9ToV10`** — strips the redundant `gameName` field from every round and
  pending round. The field was written alongside `gameId` as a human-readable
  label but was never read back — all load paths look up the game exclusively by
  `gameId`. Removing it keeps stored data lean and the model the canonical source
  of names.

**When you change a stored shape: append one new `StorageMigration` step, add it
to the registry, and bump `currentStorageVersion` — never edit an existing step
(they are historical) and never silently break old saves.**

### Settings persistence ([`settings_storage.dart`](lib/state/settings_storage.dart))

All app settings live in a single versioned blob under the `settings` key in
`SharedPreferences`. The format mirrors `game_history` — envelope + migration
framework — but operates independently (a change in one does not require a
change in the other).

**Key:** `settings`.  
**Envelope (`currentSettingsVersion` = 1):** `{ "version": 1, … }`.

**Shape (v1):**
```jsonc
{
  "version": 1,
  "themeMode": "system",          // ThemeMode enum name
  "ruleVariants": {
    "starterVariant": "dealerStarts",          // StarterVariant enum name
    "heartsVariant": "onlyAfterPlayedHeart"    // HeartsVariant enum name
  }
}
```

`ruleVariants` uses the same field names as `RuleVariants.toJson()` in
`game_history` (`starterVariant`, `heartsVariant`), but the two serialisations
are independent — a future rename in one does not force a change in the other.

**Load behavior (`loadPersistedSettings`, called in `main()` before `runApp`):**
- Missing `settings` key → **bootstrap** from legacy flat keys
  (`theme_mode`, `default_starter_variant`, `default_hearts_variant`) if
  present; else build a fresh v1 defaults map. Write the versioned blob and
  delete any legacy keys.
- `version > currentSettingsVersion` → throw
  `UnsupportedSettingsVersionException`.
- `version < currentSettingsVersion` → run `runSettingsMigrations`, write
  back.
- Any JSON/cast error → throw `CorruptSettingsException`.
- On error, `main()` catches and stores the error in
  `settingsLoadErrorProvider`. `HomeScreen` watches it and shows a
  `_StorageErrorScreen` in place of the home body ("Instellingen wissen"
  resets to defaults without a restart).

**Write path:** each notifier calls `updateSettingsField(section?, key, value)`
after a user change — a read-modify-write on the `settings` blob.

**Migration framework ([`settings_migrations.dart`](lib/state/settings_migrations.dart)).**
Identical pattern to [`migrations.dart`](lib/state/migrations.dart):
`SettingsMigration` declares `fromVersion` and `apply(Map<String, dynamic>)`;
`runSettingsMigrations` chains the steps.

**When you change a stored settings shape: append one new `SettingsMigration`
step and bump `currentSettingsVersion` — same rules as game-history migrations.**

**State files:**

| File | Role |
|------|------|
| [`settings_storage.dart`](lib/state/settings_storage.dart) | Load, write, bootstrap, error types, `settingsLoadErrorProvider` |
| [`settings_migrations.dart`](lib/state/settings_migrations.dart) | `SettingsMigration` base, `currentSettingsVersion`, registry |
| [`storage_exceptions.dart`](lib/state/storage_exceptions.dart) | `HasCause` interface shared by `CorruptStorageException` and `CorruptSettingsException` |
| [`theme_mode_provider.dart`](lib/state/theme_mode_provider.dart) | Writes `themeMode` field via `updateSettingsField` |
| [`enum_preference_notifier.dart`](lib/state/enum_preference_notifier.dart) | Generic base; subclasses declare `settingsKey` + `settingsSection` |
| [`default_starter_variant_provider.dart`](lib/state/default_starter_variant_provider.dart) | `ruleVariants.starterVariant` |
| [`default_hearts_variant_provider.dart`](lib/state/default_hearts_variant_provider.dart) | `ruleVariants.heartsVariant` |

### Backup / export-import ([`export_import_notifier.dart`](lib/state/export_import_notifier.dart))

The export-import subsystem lets users back up both persisted streams (game
history + settings) to a ZIP file and restore them on the same or a different
device. Stored blobs flow through their normal migration runners at import time;
the subsystem adds no extra migration hooks of its own. `currentBackupVersion = 1`
(in `backup_migrations.dart`) versions the ZIP envelope.

**ZIP envelope.** `exportBackup()` writes a ZIP with up to three entries:

```
manifest.json   {"version":1, "appVersion":"…", "exportedAt":"… (local ISO-8601)",
                 "utcOffset":"+HH:MM", "contains":[…], "hashes":{…}}
games.json      raw SharedPreferences blob — exactly the {version, games} JSON
settings.json   raw SharedPreferences blob — exactly the {version, themeMode, …} JSON
```

Each file's SHA-256 is stored in the manifest. Neither blob is transformed —
the import path runs the normal migration runners on them.

**Two-phase import.** `analyzeBackup()` is a **read-only** pass: it decodes,
validates hashes, runs migrations, and runs content validation — but writes
nothing. It returns `ImportAnalysis` describing what the backup contains and
whether each stream can be imported. `ImportNotifier.applyImport()` (a
`Notifier<void>`) re-runs the same migrate+validate pass as its authoritative
gate, then commits the streams. Validating both before the first write makes the
commit **validation-atomic**: a *validation* failure in either stream leaves
storage untouched. The two streams live under separate SharedPreferences keys
with no cross-key transaction, so the residual case — a low-level write failure
*after* one stream already committed — is surfaced, not hidden: `applyImport`
throws `PartialImportException` carrying what did commit, and `ImportScreen`
tells the user exactly which data was/wasn't restored. (A failure with nothing
committed is surfaced as the original error.) The commit calls
`GameHistoryNotifier.replaceAll()` for games and `ThemeModeNotifier.setMode()` +
variant notifier setters for settings (never `ref.invalidate` — that would
rebuild from the old startup value). The calculator is reset **only when games
are replaced** (so a pending autosave can't resurrect the overwritten session);
a settings-only import leaves any in-progress game untouched.

**Zip-bomb protection.** Two guards: a raw-input-size check (`_maxBackupFileBytes`,
on the actual file length, which can't lie) before decoding, and — after decode —
a rejection of archives with > 3 entries or > 10 MB *declared* uncompressed total
(best-effort, since a crafted header could understate sizes) before reading any
content. Both run in `analyzeBackup` and `applyImport`.

**Validation layers.**
- `lib/models/game_constraints.dart` — pure domain; the single source of the
  *rules*: `kPlayerNameMaxLength` / `kGameNameMaxLength` and predicate/normalizer
  functions (`normalizePlayerName`, `duplicatePlayerNameIndices`,
  `allPlayerNamesFilled`, `normalizeGameName`, …).
- `lib/models/game_invariants.dart` — pure domain; `GameInvariantError` +
  `assertGameInvariants(GameSession)` (engine-level: score sums, round sequence,
  counts; name uniqueness via the `game_constraints` predicate).
- `lib/state/validation.dart` — `ValidationError`; `validateManifest` (version,
  appVersion, exportedAt, contains, hashes), `validateMigratedGames` (calls
  `assertGameInvariants` + composes the `game_constraints` predicates for player
  name length/non-empty/case-insensitive uniqueness, gameName length/non-empty),
  `validateMigratedSettings`; `validateGameSession` (per-game subset of
  `validateMigratedGames` without duplicate-id check).

**`game_constraints.dart` is the single source of truth for valid game data.**
The rules for player/game names live there once, as **predicates** (boolean /
normalizer functions) so every layer composes the same logic rather than
re-deriving it:

- **Engine asserts + import/write validation** — `game_invariants` and
  `validation.dart` call the predicates and throw their own error type on
  failure. `gameHistoryProvider.saveGame` calls `validateGameSession` before
  persisting; `settings_storage.updateSettingsField` calls
  `validateMigratedSettings` before every write.
- **Create/edit UI** — `new_game_screen` (`canStart`), `edit_game_screen`, and
  `player_list_field` (duplicate highlight) call the predicates directly; input
  field `maxLength` / formatters reference `kPlayerNameMaxLength` /
  `kGameNameMaxLength` from `game_constraints`, never re-declaring them.
- **`replaceAll`** (import commit path) is the deliberate exception: it is called
  only after `validateMigratedGames` has already run in the analyze pass, so
  double-validation is skipped.

**Backup migrations** (`backup_migrations.dart`). Same frozen/sequenced pattern
as `StorageMigration` / `SettingsMigration`. Currently empty (`backupMigrations
= []`, `currentBackupVersion = 1`). Append a `BackupMigration` step here when
the ZIP envelope structure changes (never reorder or remove).

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
  Also has a "Gegevens" `FormSectionCard` with two `ListTile`s that push
  navigation screens (back arrow, not fullscreen dialog):
  - *Exporteer gegevens* → `ExportScreen`; scope radio (all / games only /
    settings only) + share via `shareFile()`.
  - *Importeer gegevens* → `ImportScreen`.
- **`ExportScreen`** — scope selection + export trigger; pushes onto the
  navigator stack (back arrow). Calls `exportBackup` + `shareFile`; pops on
  success, shows snackbar on failure.
- **`ImportScreen`** — sealed state machine (`_Idle → _Analyzing → _Analyzed →
  _Applying`); idle shows "Kies bestand" (`FilePicker.pickFile`); analyzed shows
  `_BackupInfoCard` + `_ImportOptionsCard` (checkboxes) + zero-games warning;
  applies via `ImportNotifier.applyImport`; success snackbar shown before pop.
- **`GameScreen`** — the in-game hub; a `ConsumerStatefulWidget` whose `dispose()`
  schedules `flushAndReset()` via `addPostFrameCallback` (subscriptions are
  cancelled by Riverpod only after `dispose()` returns; the callback fires after
  `finalizeTree()` drains them all, so the `NoSession` transition is safe).
  A `sessionId` guard prevents resetting a session loaded during the animation.
  Back-navigation therefore never loses a debounced autosave. `_GameSelectionBody`
  separates unplayed and played games per category (negative / positive); played
  games are hidden by default and can be revealed via a per-category toggle in
  `_SectionHeader` — when visible they render disabled ("Spel al gespeeld") and
  offer force-replay on tap. When all games in a category are played and the toggle
  is off, a greyed-out `_AllGamesPlayedCard` fills the otherwise-empty section; it
  hides when the toggle is on (the played tiles themselves provide the content).
  Per-chooser quota disabling and pending-round blocking
  remain as soft disables. Also contains `_LiveScoreboard`, a round-history list,
  and edit-game / delete-game actions. When the game is **finished**, the app bar
  shows a *Deel uitslag* (share) action that exports the result as a rendered PNG
  (an off-screen `_ShareCard`, captured via `RepaintBoundary.toImage`) with a
  plain-text fallback; a popup dialog offers an explicit image/text choice and a
  `CustomSemanticsAction` exposes it to assistive tech. Uses `share_plus`
  (+ `path_provider` for the temp file on mobile; the web branch uses
  `XFile.fromData`).
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
  `rulesEditModeProvider`; the mode (set by `RulesIconButton`'s `ProviderScope`)
  controls whether the cog opens the picker (`enabled`), is hidden
  (`hidden`), or shows a snackbar directing to 'Spel bewerken'
  (`disabled`).

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
  `scoring_doubles_test`), `double_matrix_test`, `game_session_test`
  (incl. corrupt-data / dangling-id rejection via `_validateReferences`),
  `mini_game_test` (incl. the input↔counts storage converters),
  `game_mechanics_test` (dealer rotation + per-chooser quota + `seatIndexOf`
  throw-on-unknown), `score_result_test`.
- **`test/models/`** also has `game_invariants_test.dart` —
  `assertGameInvariants` happy path + each invariant violation — and
  `game_constraints_test.dart` (the shared name predicates/normalizers).
- **`test/state/`** — `calculator_provider_test`, `game_history_provider_test`
  (incl. migration, corrupt data, unsupported-version handling, and
  `CorruptStorageException` end-to-end for dangling player-id references),
  `validation_test` (`validateManifest` / `validateMigratedGames` /
  `validateMigratedSettings`), `export_import_test` (`exportBackup` round-trip,
  hash verification, `analyzeBackup` valid/corrupt/version/stream errors,
  zip-bomb guard), `apply_import_test` (`replaceAll`, `applyImport` full
  round-trip, games-only, settings-only live update, pending round,
  no-partial-write guard).
- **`test/widgets/`** — one file per screen/widget.
- **`test/data/`** — `game_rules_test.dart`: variant coverage + coupling test
  (every `kGameSections.gameId` exists in `allGames`).
- **`test/tool/`** — pure-logic tests for the `tool/` helper libraries
  (`semver`, `pubspec_yaml`, `pubspec_lock`, `google_fonts_parser`,
  `flutter_release`, `gha_pins` — action/Ubuntu-runner pin parsing + bumping —,
  `fastlane_pin`). No network, no subprocess — only the extracted helpers.
- **Guards:** `architecture_test.dart` fails the build if any screen uses raw
  `Scaffold` instead of `AppScaffold`, or if any file calls
  `showModalBottomSheet` directly instead of `showAppBottomSheet`;
  `license_assets_test.dart` verifies: all four bundled font `.ttf` files appear
  in the asset manifest (drift guard for `google_fonts` version bumps); the Arimo
  SIL OFL entry appears in `LicenseRegistry` (compliance gate); the
  `Arimo-LICENSE.txt` asset resolves at runtime; and the root AGPL `LICENSE`
  asset resolves; `a11y_test.dart` pumps every
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
- **Platform side-effects are injected via providers, never via test-only
  constructor params.** The share sheet and file picker are reached through
  `shareFileProvider` / `shareTextProvider` / `pickBackupBytesProvider`
  ([`platform_io_providers.dart`](lib/state/platform_io_providers.dart), thin
  wrappers over [`share_service.dart`](lib/services/share_service.dart) /
  [`file_pick_service.dart`](lib/services/file_pick_service.dart)). Tests swap
  them with `ProviderScope.overrides` / `ProviderContainer(overrides: …)` to
  drive the share-refused and file-pick flows. **Do not** inject test behaviour
  through `@visibleForTesting` constructor params or runtime debug branches —
  that ships a never-taken branch and a test-only API in the production widget.
  (`@visibleForTesting` on a *pure function that production also calls*, e.g.
  `rankScores` / `buildShareText`, is fine — it only relaxes visibility, adds no
  runtime branch.) Note `_captureShareCard`'s real PNG capture is left
  un-mocked rather than seamed, so `GameScreen`'s image path isn't widget-tested
  (its boolean handling mirrors the export-refused path that is).

---

## 12. Build, run & release

Flutter SDK version is pinned in [`.fvmrc`](.fvmrc). CI installs it from there
via the `setup-build` action. Always use `fvm flutter`/`fvm dart` locally to run
against the pinned version. Bump the pin to the latest **stable** release with
`fvm dart run tool/update_flutter.dart` — it rewrites `.fvmrc`, the `pubspec.yaml`
Dart `sdk:` lower-bound, and the Android toolchain versions together, then runs
`fvm install`. Exits without writing when already current (`--force` re-runs
`fvm install` + Android sync anyway; [`--check`](tool/update_flutter.dart) reports
without writing). Never downgrades if the pin is ahead of stable.

### Common commands

```bash
fvm flutter pub get
fvm flutter run                                       # Android device / emulator
fvm flutter run -d chrome                             # Web
fvm flutter test                                      # All tests
fvm flutter analyze                                   # Static analysis (lints from analysis_options.yaml)
fvm dart format .                                     # Auto-format all Dart (run before committing)
fvm dart format --output=none --set-exit-if-changed . # Formatting check (what CI runs; exits 1 on drift)

fvm flutter build apk --release                       # Android APK
fvm flutter build appbundle --release                 # Android AAB (Play Store)
fvm flutter build ipa --release                       # iOS/iPadOS (needs macOS + signing)
fvm flutter build web --release --base-href /bonken/  # Web (GitHub Pages)
```

### CI quality gates

The [`verify`](.github/actions/verify/action.yml) composite action (run by the
`develop` and `release` workflows) enforces **three** gates in order:
`dart format --output=none --set-exit-if-changed .`, `flutter analyze --fatal-infos`,
and `flutter test`. Run all three locally before pushing. **Coding agents:** also
run `fvm dart format .` — formatting drift fails CI just like an analyzer error.

`dart fix --dry-run` is also part of `verify` — CI fails if the analyzer proposes
any auto-fix. Run `fvm dart fix --apply` locally to clear drift before pushing.

**The analyzer is intentionally strict — a deliberate design choice, not inherited
defaults.** It is used as an active quality gate so coding discipline is enforced
by the toolchain: it pushes whole error classes to analyze-time (e.g. unguarded
`dynamic` / cast bugs at the JSON boundary), forces deliberate choices (every
`catch` names what it handles; stray futures must be awaited or explicitly
discarded), and keeps the code uniform (explicit types and return types, stable
formatting). The full rule set — each entry with a short note — is in
[`analysis_options.yaml`](analysis_options.yaml). In practice: write explicit
types and return types, and wrap fire-and-forget futures in `unawaited(...)`.

### Versioning & release

`pubspec.yaml` carries a sentinel `0.0.0+0`; CI passes `--build-name` /
`--build-number` from the git tag / run number.

A `MAJOR.MINOR.PATCH` git tag triggers [`release.yml`](.github/workflows/release.yml):
it builds web (attached to the GitHub Release), Android (AAB → Play Console
*alpha* track as a draft), and iOS (universal IPA → App Store Connect *TestFlight*).
Both store uploads run through **fastlane** — `supply` for Android
([`android/fastlane/`](android/fastlane/)), and `match` (code signing via a
separate private certs repo) + `pilot` for iOS ([`ios/fastlane/`](ios/fastlane/),
on a `macos-latest` runner). The Android upload lands in the Play Console alpha
track as a draft; the iOS upload lands in TestFlight. In both cases, publishing to
end users stays a manual step (promoting the draft / submitting for App Store review).

Each store upload job is gated on a repo **variable** so one can be disabled
without affecting the other: `ANDROID_RELEASE_ENABLED` gates the whole Play path
(the AAB build + its upload — the APK + web still build for the GitHub Release),
and `IOS_RELEASE_ENABLED` gates the *entire* `release-ios` job (no macOS runner
is even spun up when it is off).

Android signing secrets live in the `play-store` GitHub environment; iOS
signing/API secrets in the `apple-app-store` environment. API keys are scoped by
least privilege: the per-tag release only ever uses an *App Manager* key
(read-only `match` install + TestFlight upload), while creating/renewing the
certificate needs an *Admin* key, loaded **only** by the manual `workflow_dispatch`
[`renew-ios-signing.yml`](.github/workflows/renew-ios-signing.yml) job (no Mac
needed). iOS distribution certificates expire yearly; renewal is that same manual
workflow.

**fastlane** is major-pinned (`gem "fastlane", "~> 2"`) in `android/Gemfile` +
`ios/Gemfile` — not exact, since it only runs in CI with no local setup to
validate a bump. `~> 2` lets minor/patch fixes flow but holds back a new major
that could break the pipeline. `fvm dart run tool/update_gha.dart` reports
(without changing anything) when a new fastlane major ships; bumping it is then a
deliberate manual edit.

### GitHub Actions & runners

Actions are pinned either to a major tag (`@v6`) or, for actions without a moving
`vN` (e.g. the OSV scanner), to a specific version (`@v2.3.8`). The Ubuntu runner
is pinned (`runs-on: ubuntu-24.04`); `macos-latest` stays floating so iOS builds
track current Xcode.

`fvm dart run tool/update_gha.dart` checks the whole CI toolchain in one pass: it
bumps any out-of-date **action** in place — to the newest major for major pins,
the newest `vX.Y.Z` for version pins, including subdirectory actions (`--check`
only reports) — and **reports** (never changes) when a newer **Ubuntu LTS runner**
image or **fastlane major** is available, since those bumps are deliberate (a
fastlane major may need Fastfile edits; a new Ubuntu can rename packages). Set
`GITHUB_TOKEN` to avoid the 60/h unauthenticated rate limit.

### Fonts

Roboto (text) and Arimo (suit glyphs ♠♥♦♣, which Roboto lacks) are bundled under
`assets/google_fonts/<version>/` and loaded via the `google_fonts` package with
runtime fetching disabled (offline + deterministic suit glyphs). The Arimo SIL OFL
license is bundled alongside the `.ttf` as `Arimo-LICENSE.txt` and registered via
`registerBundledLicenses()` in `main.dart` so it surfaces in `showLicensePage()`.
Roboto's license is already covered by the Flutter engine NOTICES (it is Flutter's
default font).

Upgrade all bundled fonts with `fvm dart run tool/update_fonts.dart` — it bumps
the `google_fonts` pin, downloads matching `.ttf`s + the Arimo license, and
rewrites the `pubspec.yaml` asset path atomically.

### Launcher icons & splash screens

`./tool/generate_icons.sh` renders SVG sources to PNGs, runs `flutter_launcher_icons`
(config in `pubspec.yaml`), and generates all platform splash images and PWA icons.
Requires `rsvg-convert` (`apt install librsvg2-bin`) and `fc-match`/`fc-query`
(`apt install fontconfig`); CI installs both in `setup-build`. Locally the script
requires `fvm`; CI passes `--ci` so it uses PATH `dart` directly. Do not run
`fvm dart run flutter_launcher_icons` directly: it skips the intermediate 1024 px PNGs,
all web icon and splash-screen generation, and the font-sandbox sanity check.

**Font sandbox:** the script builds a throwaway `FONTCONFIG_FILE` exposing *only*
`assets/google_fonts/<version>/`, so suit/word glyphs rasterise from the same
`.ttf`s the app ships (no system-font drift). Its sanity check is **asset-driven**:
every bundled `.ttf` must resolve, through the sandbox, back to itself. That stays
exhaustive as font cuts change, but it deliberately does **not** verify that the
families the SVGs *reference* are bundled — so a future SVG naming an unbundled
family/weight would silently fall back rather than error. Today the SVGs reference
only `Roboto` and `Arimo` at weight 400, both bundled; keep new SVG glyphs within
the shipped cuts.

**SVG sources** — two card sizes are in use, driven by platform constraints:

*62.5 % card* (viewBox `0 0 1024 1024`): `icon_bonken.svg` (gradient background)
and `icon_bonken_flat.svg` (solid `#283593` background). iOS only rounds corners —
no circle mask — so no safe-zone padding is needed and the card can fill more of
the canvas.

*50 % card* (viewBox `−128 −128 1280 1280`): `icon_bonken_adaptive_fg.svg`
(transparent), `icon_bonken_padded.svg` (gradient background), and
`icon_bonken_adaptive_bg.svg` (gradient background layer only). The extra padding
is required for Android's strict-circle launcher mask; see **Safe-zone calibration**
below. This size is also used for all native and PWA splash screens and the HTML
loading screen, so the splash card appears visually consistent across platforms even
though the launcher icon is larger on iOS.

The card coordinates, radii, and suit positions are **identical** in all four SVGs;
only the viewBox and background differ.

**Launcher / home-screen icons** (what appears in the app grid after install):

- *Native iOS*: `flutter_launcher_icons` generates `AppIcon.appiconset` from
  `icon_bonken.png` (`icon_bonken.svg`, 62.5 % card). `remove_alpha_ios: true`
  flattens transparency onto `background_color_ios: "#283593"`; the gradient source
  is already opaque. Generating the appiconset needs the `ios/` Runner project and
  runs only on macOS/Xcode.
- *iOS PWA (apple-touch-icon)*: `Icon-apple-touch.png` rendered from
  `icon_bonken_flat.svg` (62.5 % card, solid `#283593` background), referenced by
  `<link rel="apple-touch-icon">` in `index.html`. Same card size as the native iOS
  launcher icon. Using the transparent `Icon-192.png` instead would let Safari
  composite the card on white.
- *Native Android*: `flutter_launcher_icons` generates adaptive icon layers —
  foreground from `icon_bonken_adaptive_fg.png` (transparent, 50 % card) +
  `icon_bonken_adaptive_bg.png`; legacy fallback from `icon_bonken_padded.png`
  (50 % card, gradient). `android:inset="10%"` on the foreground; see
  **Safe-zone calibration** below.
- *Android PWA*: Chrome picks `Icon-maskable-{192,512,1024}.png` (from
  `icon_bonken_padded.svg`, 50 % card, gradient background) for the home-screen
  icon; falls back to non-maskable `Icon-{192,512,1024}.png` (transparent, 50 %
  card, from `icon_bonken_adaptive_fg.svg`). All six sizes listed in the static
  committed `manifest.json`.

**Splash screens** (shown while the app loads, before any UI is interactive):

- *Native iOS*: `LaunchScreen.storyboard` centres `LaunchImage.png` (1×/2×/3× at
  200/400/600 px, from `icon_bonken_adaptive_fg.svg`, 50 % card) on `#283593`.
  Image assets are gitignored.
- *iOS PWA*: iOS auto-generates a splash from the `apple-touch-icon`; card size
  matches the home-screen icon (62.5 %).
- *Native Android (API 21–30)*: `launch_background.xml` centres `splash_logo.png`
  (200–800 px at five density buckets, from `icon_bonken_adaptive_fg.svg`, 50 % card,
  ~200 dp) on `#283593`. Image assets are gitignored.
- *Native Android (API 31+)*: `values-v31/styles.xml` sets
  `windowSplashScreenBackground` (`#283593`), `windowSplashScreenAnimatedIcon`
  (`@drawable/splash_logo` — the same transparent card as API 21–30), and
  `windowSplashScreenIconBackgroundColor` (`#283593`). Without the explicit icon,
  API 31+ auto-uses the full adaptive launcher icon including its gradient circle,
  which is visually inconsistent with the flat-indigo splash on older API levels.
- *Android PWA*: Chrome auto-generates a splash from `background_color: "#283593"`
  in `manifest.json` and the best-matching manifest icon (maskable, clipped to a
  circle).
- *Web (HTML loading screen)*: `index.html` shows a `#283593` full-screen div with
  `Icon-192.png` at 96 × 96 px CSS (50 % card, from `icon_bonken_adaptive_fg.svg`)
  and an animated progress bar; the div fades out on `flutter-first-frame`. This
  runs during JS/Flutter download inside the browser tab and is distinct from the
  PWA splash — it appears for both installed-PWA and plain-browser visits.

**Safe-zone calibration:** `icon_bonken_padded.svg` and `icon_bonken_adaptive_fg.svg`
both use viewBox `−128 −128 1280 1280` (card at 50 % of canvas). The native
`android:inset="10%"` (`adaptive_icon_foreground_inset` in `pubspec.yaml`) shrinks
the foreground to 80 % of the 108 dp canvas, so adaptive corners are ~8–10 px
inside the 36 dp safe zone (at 3–4× DPI). The PWA maskable corners are ~7 px
inside the 40 %×1280 = 512 SVG-unit safe zone on the 512 px icon file. If
`adaptive_icon_foreground_inset` or the card geometry changes, recalculate both
margins.

**Why the card isn't larger (do not "fix" the visible gap):** the card corner
reaches 1.545× its half-width (rounded-rect geometry), so at the current sizing it
already sits at ~93 % (adaptive 36 dp safe zone) / ~96.6 % (maskable 40 % radius)
of the *circle* safe-zone edge — near the maximum that guarantees no corner-clipping
under a **circle** mask. On generous masks (Samsung/OneUI & Apple squircles, MIUI
rounded-square) the card looks small with a visible gap to the edge, because a
squircle bulges past the inscribed circle the card is sized for. That gap is
intrinsic: closing it (enlarging the card) pushes the corners outside the circle
and clips them for every **circle-shape** user — stock Android/Pixel default, and
Samsung/OneUI when the user selects the circle icon shape. The exact circle-safe
maxima are inset 6.9 % / viewBox 1236 (only ~9 % / ~3.6 % bigger — marginal), so
the gap cannot be meaningfully reduced without sacrificing the no-clip guarantee.
This was a deliberate decision; keep it.

`icon_bonken.svg` (gradient) also serves as the Play Store listing icon and the
About-dialog icon.

### Store screenshots

Run `fvm dart tool/generate_screenshots.dart` with `--android <phone|tablet|all>`
or `--ios <iphone|ipad|all>` (iOS requires Xcode) to take store screenshots. It
uses Flutter's `integration_test` SDK package with `flutter drive`: the integration
test (`integration_test/screenshot_test.dart`) navigates the app to each UI state
and signals the host driver (`test_driver/screenshot_driver.dart`) via stdout
markers; the driver captures the full device screen via `adb exec-out screencap`
(Android) or `xcrun simctl io … screenshot` (iOS) and writes to
`screenshots/<platform>_<device-type>_<name>.png` (e.g. `android_phone_01_home.png`).

Two `testWidgets` sessions use a pre-seeded SharedPreferences fixture
(`integration_test/screenshot_fixtures.dart`) — session A covers the home,
new-game, and final-score screens; session B covers the round-input screens and the
rules page. All device and locale config is declared as consts inside the script
itself; `--print-env` outputs the Android values as `KEY=VALUE` lines for CI.

Manual triggers [`Screenshots – Android`](.github/workflows/screenshots-android.yml)
and [`Screenshots – iOS`](.github/workflows/screenshots-ios.yml) run the pipeline
in CI (phone + tablet for each platform) using
`reactivecircus/android-emulator-runner@v2` for Android and the pre-installed
Xcode + simulators on `macos-latest` for iOS; the result is uploaded as a
downloadable artifact for review before manual store upload. Local Android mode
manages the full AVD lifecycle (dependency-preflight, create + boot + test + kill);
pass `--clean` to force a cold boot (wipes userdata, skips and deletes any saved
Quickboot snapshot). `integration_test` and `flutter_driver` are declared as
`dev_dependencies` with `sdk: flutter` — they live in the Flutter SDK and are
skipped by `update_deps.dart` (no version field in `pubspec.lock`).

### Dependency updates

`fvm dart run tool/update_deps.dart` runs `fvm flutter pub upgrade` and rewrites
every caret constraint in `pubspec.yaml` to match the resolved version from
`pubspec.lock` (the manifest-rewriting half that `pub upgrade` deliberately omits).
Non-caret Dart pins (e.g. `google_fonts`) are left untouched.

### App update check

`services/app_updater.dart` checks Google Play for a newer build (Android only;
no-op on web/iOS/sideloaded; never blocks startup).

---

## 13. Deferred upgrades

Items that were evaluated but cannot be adopted yet due to upstream blockers.
Re-evaluate each time Flutter or the relevant dependency is upgraded.

### `android.builtInKotlin=true` (AGP 9+ built-in Kotlin)

**What:** Let AGP provide the Kotlin Gradle Plugin instead of declaring it
manually in `android/settings.gradle.kts`. Removes the explicit Kotlin version
pin and lets AGP coordinate JVM targets automatically.

**Blocked by:** `in_app_update` 4.2.5 ships its own KGP in its `buildscript`
block, which conflicts with AGP's builtInKotlin mode and causes a
NullPointerException at Gradle configure time. The package (latest as of
2026-06) has no update available.

**When to retry:** When `in_app_update` (or a drop-in replacement) publishes a
version that does not embed its own KGP, or when the package is removed from the
project.

**What to do:** Set `android.builtInKotlin=true` in `android/gradle.properties`,
remove the `id("org.jetbrains.kotlin.android")` line from
`android/settings.gradle.kts`, drop the `kotlin` field from
`tool/helpers/android_versions.dart` and the corresponding sync loop in
`tool/update_flutter.dart`.

---

### `android.newDsl=true` (AGP 9 new Gradle DSL)

**What:** Migrate to the new AGP 9 declarative DSL (`ApplicationExtension`
instead of the legacy `android { }` closure), which becomes mandatory in AGP 10.

**Blocked by:** `dev.flutter.flutter-gradle-plugin` (Flutter's own Gradle
plugin) does not support the new DSL yet — enabling it causes an NPE in plugin
application.

**When to retry:** When Flutter upgrades its Gradle plugin to support AGP 9 new
DSL. Watch Flutter release notes for "AGP 9 new DSL" or "newDsl" mentions.

**What to do:** Set `android.newDsl=true` in `android/gradle.properties` and
migrate `android/app/build.gradle.kts` from the legacy `BaseAppModuleExtension`
(`android { }`) to `ApplicationExtension`.

---

### `file_picker` stable 12.x (currently pinned to a beta)

**What:** `pubspec.yaml` pins `file_picker: '>=12.0.0-0 <13.0.0'` — a
pre-release. It is the cross-platform picker for importing backup ZIPs.

**Blocked by:** `file_picker` v8–11 depend on `win32 ^6`, which conflicts with
`package_info_plus ^10`'s `win32` constraint; only the v12 beta resolves it
without a manual `win32` dependency override.

**When to retry:** When `file_picker` publishes a stable 12.x.

**What to do:** Tighten the constraint to the stable release (e.g.
`file_picker: ^12.0.0`) and re-run `fvm flutter pub get`.

---

## 14. Conventions & invariants (quick reference)

Things to *not* break:

- **Always 4 players, 12 rounds** (`playerCount`, `GameSession.totalRounds`).
- **Key everything by player UUID**, never seat index; derive indices on demand.
- **Σ scores == `totalPoints`** for every game — the engine invariant (asserted).
- **Seat-relationship math lives only in `game_mechanics.dart`** — don't
  re-derive "dealer = chooser − 1" or "starter = …" elsewhere. This includes
  `starterIndexFor`, which takes a `StarterVariant` and lives here. (The
  `List<Player>` lookup/rotation helpers `seatIndexOf` / `rotatedFromDealer` are
  not relationship math and live with `Player` in `player.dart`.)
- **Screens use `AppScaffold`** (architecture test enforces it).
- **Bottom sheets use `showAppBottomSheet`**, never `showModalBottomSheet`
  directly (architecture test enforces it).
- **Icons are `Symbols.*` only** — never the legacy `Icons`.
- **`gameById` and `seatIndexOf` throw on an unknown id** — never rely on a
  silent fallback. An unknown id from stored JSON is caught at the load boundary
  (`GameSession.fromJson` calls `_validateReferences`; any throw becomes
  `CorruptStorageException` via `GameHistoryNotifier.build()`'s `on Object`
  catch). An unknown id after load is a programming error; throwing makes it loud.
- **`CalculatorState` is sealed: `NoSession` vs `ActiveSession`.** "No session
  active" is `state is NoSession`, not an empty `sessionId` or `firstDealerId`
  sentinel. `ActiveSession` requires a valid `firstDealerId` / `dealerId` /
  `chooserId` (the factory makes them `required`; storage loads pass through
  `_validateReferences`), so its seat-index getters delegate to the throwing
  `seatIndexOf` — an invalid id surfaces a programming bug instead of silently
  resolving to seat 0.
- **Derived lists watched by `select()` must keep stable identity** — store them
  as fields, recompute in `copyWith` only when inputs change.
- **`pending` is sealed** — branch with `is ActivePendingRound`; never resurrect
  the old "three nullable fields" pattern.
- **Section and card titles use `Semantics(header: true)`** — `FormSectionCard`
  does this automatically; hand-written cards must add it explicitly.
- **Append a `StorageMigration` step + bump `currentStorageVersion`** when
  changing stored JSON shape (never edit an existing, frozen step).
- **UI strings in Dutch, code identifiers in English.**
- **Run `fvm dart format .` before committing** — CI's `verify` action fails on
  unformatted Dart (`dart format --output=none --set-exit-if-changed .`).
- **Update AGENTS.md / ARCHITECTURE.md as part of the change** when it affects
  documented architecture, conventions, the storage version, the directory map,
  or invariants — not as a follow-up.

---

## 15. Glossary (Dutch → English)

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
