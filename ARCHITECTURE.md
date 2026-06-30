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

- **Platform:** Flutter. Primarily ships as native **Android** (APK/AAB on
  Google Play) and **iOS/iPadOS** (universal app on the App Store / TestFlight)
  builds, plus an offline-first **PWA** (web, installable on Android/iOS/desktop;
  used mainly for testing).
- **Fully offline / local-only:** no backend, no accounts, no network in the
  core flow. All data is in `SharedPreferencesAsync`. Fonts and licenses are bundled
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
  the load boundary and surfaced as `CorruptPersistenceException`) or a programming
  bug — neither should silently substitute a wrong player/game.
  The bootstrap follows the same posture but handles failures **at the boundary**,
  not through a global catch-all. Each failable step is guarded individually: a
  settings load failure surfaces the storage-error screen (§9), and a
  `PackageInfo` read failure routes to `BootErrorScreen` (§8) instead of
  fabricating a legacy/normal branch. Framework errors keep Flutter's default
  `presentError` (report, non-fatal). Persistence **write** failures split three
  ways by cause:
  - **Data bugs** (an invalid model, a broken `toJson`) — should never happen,
    so they propagate and crash loud in dev. Each write boundary encodes
    *before* writing so a serialization bug can't be mistaken for a storage
    fault.
  - **Environmental write faults** (the write itself fails — typically a full
    disk) — real, recoverable, not our fault. The boundary flags
    `saveHealthyProvider`, which drives one sticky `SaveErrorBanner` in
    `AppScaffold`; in-memory state is untouched, so the app keeps working and the
    banner clears the instant a later write succeeds. `PersistenceLifecycleSync`
    ties both lifecycle edges to persistence: on `onHide` (leaving the
    foreground) it flushes any pending debounced autosave immediately, so an OS
    kill while backgrounded can't drop edits still in the 400 ms window; on
    `onResume` — when the user has most likely just freed space — it re-flushes
    the in-memory state, so a recovered disk clears the banner without polling.
    Incidental writes (autosave, settings, saves)
    swallow the fault behind the banner; only the import path passes
    `surfaceFault` so a deliberate one-shot import reports a clean failure
    (`PersistenceWriteException`).
  - **Teardown / join races** — the debounced autosave and its on-dispose flush
    `.catchError` for a *structural* reason: the in-flight write is awaited by
    `cancelAndJoin()` on the delete/import paths (a carried error would rethrow
    inside that unrelated op), and the dispose flush tolerates the container
    being torn down mid-write.

- **Validate at the external boundary, then trust the typed result.** Untrusted
  data — an imported backup, a stored JSON blob, anything crossing into the app
  from outside — is validated **once**, where it is decoded: `BackupCodec.decode`
  / the `validation.dart` gate (`validateManifest` / `validateMigratedGames` /
  `validateMigratedSettings`) plus the models-layer `assertGameInvariants`. Past
  that boundary the parsed, typed result is trusted — internal code does not
  re-decode or re-validate what the boundary already guaranteed (e.g.
  `applyImport` commits the objects `decode` already validated). *Why:* one
  authoritative gate is auditable and cannot drift out of sync with itself;
  sprinkling defensive re-checks downstream yields partial, inconsistent
  validation and dead branches. See §9.

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

- **Primary form actions look disabled but stay tappable** (*Mechanism A*).
  Save/start buttons pass `onPressed: null` (truly disabled — native M3 colours,
  WCAG-exempt) when the form is incomplete or invalid. A transparent
  `GestureDetector` overlay (`ExcludeSemantics`, `HitTestBehavior.opaque`) sits
  on top and shows a `showTimedSnackBar` with a specific reason when tapped — the
  user sees the form is not ready *and* learns why when they tap anyway.
  `DisabledTappableButton` (`lib/widgets/disabled_tappable_button.dart`) is the
  canonical home: it derives the overlay-enable rule from the single nullable
  `onPressed`, so the "disabled ⟺ overlay-on" pairing can't drift; it composes
  the lower-level `DisabledTapDetector`
  (`lib/widgets/disabled_tap_detector.dart`) Stack+overlay primitive.
  `FullWidthBottomBarButton` and the same-disabled rules cog
  (`rules_block_view.dart`) reuse this rather than re-wiring the overlay by hand.

- **Guide with the rules, don't hard-enforce them.** The app *surfaces* the
  game's rules (amber `Note` callouts, disabled-looking affordances) but lets
  players override them — *what happens at the physical table is authoritative,
  not what the app thinks is legal*. Concretely: the per-chooser game quota is a
  **soft** disable with a "Toch doorgaan" dialog (`game_screen.dart`); the two
  doubling rules the picker would otherwise block — a redouble whose turn has
  passed, and the chooser initiating a double — are shown disabled but
  **force-able** via a confirm dialog (`doubles_picker.dart`, *Mechanism B*:
  announced as an *enabled* button that mutates on confirm — deliberately
  distinct from Mechanism A's truly-disabled snackbar gate); rule prose is data
  shown verbatim, not branching logic (§6). Code only **hard**-enforces what
  keeps data well-formed (e.g. a canonical `DoubleMatrix`, Σ scores ==
  `totalPoints`), never table etiquette.

- **Accessible by default.** Decorative `Icon`s carry no `semanticLabel`, so
  they stay out of the a11y tree; every interactive control exposes a button
  role + label — icon buttons via `tooltip`, custom `InkWell` tiles via an
  explicit `Semantics` (with `MergeSemantics` so each reads as one control).
  Dimmed-but-tappable tiles keep the dim purely visual but read as *disabled*
  (matching the dimmed look → WCAG contrast-exempt) and expose their real action
  through a custom semantics action so assistive tech isn't misled: the doubles
  **force tiles** carry `Forceren` (plus an override hint), and a non-selected
  **selectable tile** (a dimmed initiator / player pick while another is
  selected) carries `Selecteren`. The played/quota **game tiles** announce as
  buttons with an explanatory hint. Tap targets are kept at the standard ≥48dp. **Section and card titles
  use `Semantics(header: true)`** — the `FormSectionCard` widget does this
  automatically; hand-written cards add it explicitly. The four built-in
  guidelines below cannot inspect header flags, so this one clause is
  review-enforced rather than gated (no built-in guideline checks it; a custom
  semantics-tree assertion would be brittle for little gain). Invisible
  layout spacers use `ExcludeSemantics`. `test/a11y_test.dart` pumps every
  screen with semantics on and gates `textContrastGuideline`,
  `labeledTapTargetGuideline`, and `android`/`iOSTapTargetGuideline` via the
  normal `flutter test` run (no separate CI step). The `architecture_test.dart`
  meta-guard keeps the "every screen is pumped" promise honest.

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
`SharedPreferencesAsync`.

---

## 4. Directory map (`lib/`)

```
lib/
  main.dart                  Entry: bootstrap (boundary-guarded startup → error
                             screens), the one-off legacy→async prefs
                             migration (migrateLegacyPrefs, §9), theme, forced-nl
                             localization, routing/deep links, bundled-font license
                             registration (Arimo SIL OFL via registerBundledLicenses()),
                             edge-to-edge, and the Android update check (via
                             androidUpdateCheckProvider).
  utils.dart                 Pure (framework-free) cross-cutting helpers: formatDate/formatScore,
                             enumByName/enumByNameOrNull, reorder index math, shared string constants.

  models/                    Pure domain layer (no Riverpod; minimal Flutter).
    mini_game.dart           MiniGame abstract base + calculateScores engine; GameSymbol
                             sealed union; GameCategory; playerCount(4).
    game_mechanics.dart      dealerIndexFor / chooserIndexFor / starterIndexFor /
                             doublingTurnIndex — ONLY home of seat relationships.
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
    app_version.dart         AppVersion {version, buildNumber} — the app's version/build stamp,
                             shared by the About dialog (resolveAppVersion) and the backup manifest.
    games/
      game_catalog.dart      allGames — the single ordered list of all 13 mini-games; gameById()
                             — the single lookup helper (throws on unknown id).
      positive_games.dart    PositiveGame base + Clubs/Diamonds/Hearts/Spades/NoTrump.
      negative_games.dart    The 8 negative mini-games.

  state/                     Riverpod providers.
    calculator_provider.dart CalculatorState (sealed: NoSession | ActiveSession) +
                             CalculatorNotifier (the in-game state machine);
                             activeSessionProvider narrows it to ActiveSession.
    calculator_keep_alive.dart holdCalculatorAcrossNavigation(context) — keeps the
                             autoDispose calculatorProvider alive across the load→navigate gap.
    game_history_provider.dart Persistence (SharedPreferencesAsync) + versioning; runs migrations on load.
                             Also owns replaceAll(List<GameSession>) used by the import path.
    migrations.dart          Sequenced, frozen StorageMigration steps (v1→…→v11) + runner. currentStorageVersion = 11.
    settings_storage.dart    Versioned `settings` blob: load (loadPersistedSettings), bootstrap from
                             legacy keys, atomic whole-blob write (persistSettings), settingsLoadErrorProvider.
                             (Throws the shared persistence exceptions defined in storage_exceptions.dart.)
    settings_provider.dart   SettingsNotifier — the single in-memory PersistedSettings blob; per-field
                             setters + replaceAll, each persisting atomically via persistSettings.
    settings_migrations.dart Sequenced, frozen SettingsMigration steps + runner (mirrors migrations.dart).
    storage_exceptions.dart  Shared persistence-error family: PersistenceException sealed base +
                             UnsupportedVersionException / CorruptPersistenceException (HasCause)
                             for the *load* domain; PersistenceWriteException (HasCause) for a failed
                             *write* (full disk) — surfaced via the save-error banner, not the error screen.
    save_health_provider.dart saveHealthyProvider — bool flag a failed write trips (markFailed) and a
                             later success clears (markOk); drives the sticky SaveErrorBanner (§2).
    theme_mode_provider.dart Light/dark/system theme — read-only view derived from settingsProvider.
    default_starter_variant_provider.dart  App-wide default StarterVariant — derived view of settingsProvider.
    default_hearts_variant_provider.dart   App-wide default HeartsVariant — derived view of settingsProvider.
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
                             delegates the finished-game share/save/copy to ShareResultAction.
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
    boot_error_screen.dart   Terminal startup-error screen shown when the app id could not
                             be read (isLegacyApp == null), so neither HomeScreen nor
                             MigrationScreen can be chosen safely (see §8).

  navigation/app_routes.dart  AppRoutes — the imperative in-app navigation layer: every
                             Navigator.push/pushReplacement goes through one helper, which owns
                             the route options (fullscreen-dialog vs. card, push vs. replace, the
                             rules ProviderScope wrapping). The only place outside main.dart that
                             maps a destination to a concrete screen, so lib/widgets can trigger
                             navigation without importing lib/screens. (Deep-link/named routes
                             stay in main.dart's onGenerateRoute.)

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
    share_result_action.dart The finished-game *Deel uitslag* AppBar action + its whole subsystem:
                             off-screen capture pipeline, format/destination dispatch (share/save/
                             copy, image/text), the format-picker dialog, and the screen-reader
                             custom actions. Extracted from game_screen.dart.
    share_result_card.dart   The result artifact rendered off-screen for PNG capture
                             (ShareResultCard) + the pure rankScores / buildShareText helpers.
    doubles_picker.dart      Two-panel interactive doubling editor (initiators × targets).
    doubles_chips.dart       Read-only doubling summary chips (history view).
    double_state_chip.dart   Shared M3 chip for double/redouble state pills
                             (no border, compact density, bold labelMedium).
                             Used by doubles_chips.dart and doubles_picker.dart.
    selectable_tile.dart     Shared animated selection-tile chrome (Padding/InkWell/AnimatedContainer
                             /Row + MergeSemantics/Semantics(button)/Opacity); consumed by
                             selectable_player_tile.dart and the doubles-picker target tiles.
    selectable_player_tile.dart  Shared selectable tile (player pickers + doubles initiators); thin
                             wrapper over selectable_tile.dart.
    game_avatar.dart         GameAvatar (circular mini-game symbol avatar) + the
                             _GameSymbol renderer; used by the game / round-input screens.
    app_bar_widgets.dart     Reusable AppBar building blocks: AboutIconButton
                             (leading info icon → About dialog), RulesIconButton
                             (opens the rules screen via AppRoutes.openRules, optionally scoped
                             to one game; the route is wrapped in a ProviderScope that locks
                             variants when given the session's values), TitleWithRules
                             (AppBar.title with embedded rules icon), SettingsIconButton (opens
                             settings via AppRoutes.openSettings),
                             ThemeMenuButton (MenuAnchor cycling light/dark/system;
                             AlignmentDirectional.bottomEnd — the M3 overflow-menu
                             pattern), StoreBadges (web-only App Store / Google Play
                             badges in the About dialog, gated behind kIsWeb — native
                             builds came from a store; artwork in assets/store/), and
                             resolveAboutVersionLine() / openAboutDialog()
                             (@visibleForTesting).
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
    …                        dealer_picker_dialog.dart, dialogs.dart
                             (showConfirmDialog + confirmDiscard), timed_snackbar.dart +
                             game_deleted_snackbar.dart (cancel-and-replace; undo snackbar),
                             amber_warning_box.dart, player_name_field.dart,
                             player_list_field.dart, game_name_field.dart (optional
                             "Spelnaam" section, shared by new-game + edit-game),
                             primary_action_button.dart,
                             rules_block_view.dart, drag_handle.dart,
                             disabled_tap_detector.dart + disabled_tappable_button.dart
                             (Mechanism A overlay primitive + the button that composes it),
                             full_width_bottom_bar_button.dart (sole BottomAppBar CTA).

  models/
    labeled_variant.dart     LabeledVariant interface (label + description) implemented by
                             StarterVariant and HeartsVariant.
    starter_variant.dart     StarterVariant enum (dealerStarts / oppositeChooserStarts).
    hearts_variant.dart      HeartsVariant enum (onlyAfterPlayedHeart / graduatedUnlock).

  data/game_rules.dart       Static rules content (Block/Section/GameSection) for rules_screen.
                             VariantBlock (VariantKind.starter/hearts) carries textFor() and
                             shows a variant picker dialog via a settings icon.
  theme/app_theme.dart       Light/dark ThemeData builders (bonkenLightTheme /
                             bonkenDarkTheme) + the Symbols action-icon theme.
  theme/app_theme_extensions.dart  ThemeExtensions (Warning/GameSuit/DoubleState/Score colors)
                             + theme value helpers: scoreColor, disabledOnSurface, isDark,
                             kMenuItemButtonStyle.
  services/app_updater.dart  Fire-and-forget Google Play in-app update check (Android only).
  services/share_service.dart  shareFile()/shareText() — Future<void> share-sheet helpers that
                             complete on share-or-dismiss and THROW on a genuine failure (see
                             io_failure.dart); used by game_screen (score PNG + text) and
                             export_screen (backup ZIP), via platform_io_providers.
  services/io_failure.dart   OutOfSpaceException + kOutOfSpaceMessage + mapWriteFailures() — the
                             shared share/save/export failure contract: file writes throw a typed
                             OutOfSpaceException on a full disk (ENOSPC), any other error stays raw
                             (generic). Keeps the dart:io/errno knowledge in the service layer.
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
| `heartPoints` | Hartenpunten | negative | −10 | −130 | counts (Σ 13) |
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
`gameId` string + `input` + an optional typed `doubles` (`DoubleMatrix`, like
`RoundRecord`; serialized under the `doublesJson` key) so partial work
survives an app restart. Its `toJson`/`fromJson` resolve the game by `gameId` to
convert `input` to/from the uniform counts form, same as a round.

### `game_mechanics.dart` ([`game_mechanics.dart`](lib/models/game_mechanics.dart))
`dealerIndexFor(chooserIndex) = (chooserIndex − 1) mod 4` (the dealer sits to the
chooser's right; equivalently the chooser is left of the dealer).
`chooserIndexFor(dealerIndex) = (dealerIndex + 1) mod 4` — the algebraic inverse,
giving the default chooser; the calculator and the round/banner UI derive the
chooser through it instead of re-inlining `dealer + 1` (the `+ playerCount` term
mirrors `dealerIndexFor`'s defensive normalization).
`starterIndexFor(chooserIndex, StarterVariant)` — the seat index of the player
who leads the first trick: `dealerStarts` → same as the dealer; `oppositeChooserStarts`
→ `(chooserIndex − 2) mod 4`. `doublingTurnIndex(player, chooserIndex)` — a
player's position in the doubling turn order (0 = left-of-chooser, 3 = chooser);
drives `DoublesPicker` and `DoublesChips`. All these seat *relationships* live
here so this file remains the single home for the dealer/chooser/starter/doubling
formulas. (Plain `List<Player>` index lookups and display rotations — `seatIndexOf`,
`rotatedFromDealer` — are list utilities, not relationship math, and live with
`Player` in [`player.dart`](lib/models/player.dart).)
`playerCount` (4) lives in `mini_game.dart`. The dealer for round *N* is
`players[(firstDealerIndex + N − 1) mod 4]`. **Change these formulas here and
nowhere else.**

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

Helper getters: `hasPendingGame`, `hasPendingForSelectedGame` (the stash is for
the game in the live slot), `hasMeaningfulPendingInput`, `inputState`
(`InputState{none,partial,complete}` via the descriptor), `isEditingExistingRound`,
and `hasActiveChanges` (deep-equals
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
- `deleteLastRound(roundNumber)` — drop the most recent completed round
  (dealer/round roll back); identity-guarded, so it no-ops if the last round no
  longer matches `roundNumber` (e.g. another round landed across a confirm dialog).
- `exitPendingSlot` — leave the live slot *without* saving or discarding the
  pending round (Back with meaningful input on a pending round); the stash is
  already kept current by write-through in `updateInput`/`updateDoubles`.
- `setPlayersAndDealer` / `setDealer` / `setPlayerName` — player + dealer edits.
- `setStarterVariant` / `setHeartsVariant` — update one field of `ruleVariants`
  (via `RuleVariants.copyWith`) for the current session.
- `setGameName(name)` — set or clear the session's optional `gameName` (pass null
  to clear).
- `buildSession()` — snapshot state → `GameSession` (or `null` if no session id).
- `reset()` — cancel the autosave (drop the pending snapshot) and clear to
  `NoSession` (without saving).
- `cancelPendingAutosave()` — **async**: cancels the pending debounced autosave
  **and awaits any already-in-flight write** before returning. Callers about to
  mutate game history (delete, import-replace) must `await` it: a debounce timer
  that already fired leaves a `saveGame` suspended mid-write, and without the
  join it would resume *after* the delete and re-upsert the removed session.
  Awaiting forces save-then-delete ordering, so the final state is correctly
  deleted.

The shared private `_exitSlot` recomputes `dealerId`/`roundNumber`/`chooserId`
from `firstDealerId` + the *new* history length, so dealer rotation stays correct
whether you appended, replaced, deleted, or cancelled.

**Autosave.** A private `_AutosaveCoordinator` owns the whole mechanism — the
debounce timer, the latest pre-built snapshot, and the single in-flight write —
so the flush logic lives in one place rather than being hand-copied across the
notifier, and the timer/snapshot/in-flight bookkeeping has one owner. `set state`
is overridden to `schedule(buildSession())` a **400 ms debounced** write
(coalescing keystroke bursts into one SharedPreferencesAsync encode), building the
snapshot eagerly because `onDispose` can't read `state`. The snapshot is
persisted via `gameHistoryProvider.saveGame()`. Switching to a different session
first **flushes** the outgoing one's pending write (re-loading the *same* session
leaves it armed). Autosave is a no-op in `NoSession`. On back-navigation the
provider auto-disposes and `ref.onDispose` flushes the pending snapshot via a
`Future.microtask` (to clear Riverpod's dispose-frame constraint). For the delete
flow, `cancelPendingAutosave()` cancels the pending write **and joins any
in-flight one** before `deleteGame` runs, so a fired-but-unresolved save can't
resurrect the deleted session.

### `gameHistoryProvider` — persistence & suggestions
`AsyncNotifierProvider<GameHistoryNotifier, List<GameSession>>`. Loads + sorts
saved sessions (newest `scoredAt` first, ties broken by `id` so the order is
deterministic); `saveGame` (upsert by id) / `deleteGame` / `clearHistory` (writes
the canonical empty envelope). Player-name suggestions for the autocomplete live
in a separate derived **`playerNameSuggestionsProvider`** (unique names across
all sessions ranked by frequency, ties alphabetical/case-insensitive) — it
`watch`es `gameHistoryProvider`, so it recomputes only on a history change and
needs no manual cache invalidation. See §9 for storage details.

### `themeModeProvider` — theme
A read-only `Provider<ThemeMode>` derived from `settingsProvider` (the single
in-memory settings blob — see §9). The whole blob is **pre-loaded in `main()`**
via `loadPersistedSettings()` and seeded through a `settingsProvider` override,
so the first frame already paints in the chosen theme (no flash). Writes go
through `settingsProvider.notifier.setThemeMode`, which persists the blob
atomically.

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
  verwijderen" → confirm → `await cancelPendingAutosave` (joins any in-flight
  write) → `deleteGame` → pop →
  provider auto-disposes → `NoSession` on next creation)
  → a snackbar "Spel verwijderd" with "Ongedaan maken" whose action re-`saveGame`s
  the captured session. (The framework auto-dismisses the bar after its duration
  via `persist: false`; tests that don't dismiss it must drain that timer.)
- **Edit a game mid-play.** `GameScreen` → "Spel bewerken" → `EditGameScreen`
  → rename + drag-reorder + change first dealer → `setPlayersAndDealer` applies
  atomically, keeping UUIDs bound to their (new) seats.
- **Theme.** Any app bar `ThemeMenuButton` → `settingsProvider.notifier.setThemeMode`
  → whole blob persisted immediately.
- **Settings.** `HomeScreen` → `SettingsIconButton` → `SettingsScreen`; pick
  `StarterVariant` / `HeartsVariant` → `setDefaultStarterVariant` /
  `setDefaultHeartsVariant` on `settingsProvider.notifier` → whole blob persisted
  atomically.
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
  re-import in the new app. `isLegacyApp` is derived at startup from
  `PackageInfo.fromPlatform().packageName == 'com.suninet.bonken'`.
  Because that signal routes legacy users to migration, a failed `PackageInfo`
  read must **not** default to a branch (defaulting to "not legacy" would strand
  a legacy user on the normal app). On failure `main()` leaves `isLegacyApp`
  `null` and `BonkenApp` shows `BootErrorScreen` (a terminal "Bonken kon niet
  starten" screen); relaunching re-reads the platform metadata. The
  `isLegacyApp → start screen` mapping (`startScreenFor`) and the
  `/spelregels[/<gameId>]` deep-link grammar (`routeWidgetFor`) are
  `@visibleForTesting` and covered by `test/main_test.dart`.

---

## 9. Persistence & migration

Backend: `SharedPreferencesAsync` ([`game_history_provider.dart`](lib/state/game_history_provider.dart))
— the always-hits-the-store async API (no cached snapshot), backed by **DataStore
Preferences on Android** and the native store elsewhere (NSUserDefaults on
iOS, LocalStorage on web). `main()` runs a one-off
`migrateLegacySharedPreferencesToSharedPreferencesAsyncIfNecessary` before the
first read (`migrateLegacyPrefs`, idempotent + `migrationCompletedKey`-guarded,
the legacy store left intact) so existing installs' data moves into the new
backend; a failed move routes to `BootErrorScreen` and retries next launch
rather than reading a half-migrated store. This is **separate from** the app's
own versioned schema migrations below: it moves raw key→value blobs across the
backend, then the schema migrations run on the moved blobs. (Covered by
`prefs_async_migration_test.dart`.)

- **Current key:** `game_history`. **Legacy key:** `bonken_game_history`.
- **Envelope (`currentStorageVersion` = 11):** `{ "version": 11, "games": [ … ] }`.
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
- Unreadable storage → throw `CorruptPersistenceException`, surfaced by the
  `_StorageErrorScreen` ("Geschiedenis beschadigd" + "Geschiedenis wissen"
  button). Deliberately *not* silently `[]` — that would overwrite the user's
  saved games on the next write.
- `version > currentStorageVersion` → throw `UnsupportedVersionException`,
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
- **`_V10ToV11`** — normalizes stored names: trims every player name and the
  optional `gameName` (dropping a whitespace-only `gameName` to absent). The
  import/write gate now **rejects** un-normalized names, so this conforms any
  historically-stored stray-space name to that invariant — otherwise an
  export→import round-trip of old data could be rejected by the strict gate. A
  no-op for data written by the always-trimming create/edit UI.

**When you change a stored shape: append one new `StorageMigration` step, add it
to the registry, and bump `currentStorageVersion` — never edit an existing step
(they are historical) and never silently break old saves.** The three runners
(`runStorageMigrations` / `runSettingsMigrations` / `runBackupMigrations`)
**throw** (not just a debug `assert`) if the chain doesn't reach the current
version — a mis-registered or out-of-order step fails loudly in release rather
than silently shipping partially-migrated data under a current-version stamp.

### Settings persistence ([`settings_storage.dart`](lib/state/settings_storage.dart))

All app settings live in a single versioned blob under the `settings` key in
`SharedPreferencesAsync`. The format mirrors `game_history` — envelope + migration
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
- Missing `settings` key → **bootstrap**: build the **literal v1** body from the
  legacy flat keys (`theme_mode`, `default_starter_variant`,
  `default_hearts_variant`; absent keys fall back to defaults), then run it
  through `runSettingsMigrations(…, fromVersion: 1)` to reach current — exactly
  like an old on-disk blob. (Stamping literal `1` and migrating forward, rather
  than stamping a moving `current` onto a v1-shaped body, is what lets a future
  v2 step upgrade the genesis body.) Write the versioned blob and
  delete the legacy keys.
- `version > currentSettingsVersion` → throw
  `UnsupportedVersionException`.
- `version < currentSettingsVersion` → run `runSettingsMigrations`, write
  back.
- Any JSON/cast error → throw `CorruptPersistenceException`.
- On error, `main()` catches and stores the error in
  `settingsLoadErrorProvider`. `HomeScreen` watches it and shows a
  `_StorageErrorScreen` ("Instellingen wissen" resets to defaults without a
  restart) under a **bare app bar** — the theme menu and settings screen are
  stripped because they write through the very blob that failed to load, so a
  write would re-throw on the corrupt data (mirrors `MigrationScreen`).

**In-memory source of truth + write path.** After load, the whole blob lives in
`SettingsNotifier` ([`settings_provider.dart`](lib/state/settings_provider.dart))
as a typed `PersistedSettings`, seeded via a `main()`-time `settingsProvider`
override. The per-field providers (`themeModeProvider`,
`defaultStarterVariantProvider`, `defaultHeartsVariantProvider`) are **read-only
views** derived from it. A change goes through one of the notifier's setters
(`setThemeMode` / `setDefaultStarterVariant` / `setDefaultHeartsVariant`) or
`replaceAll` (import), which rewrite the **whole** blob from memory and persist
it in a single `SharedPreferencesAsync` write (`persistSettings`). This is the
analogue of `GameHistoryNotifier._persist`: there is no per-field
read-modify-write of the on-disk copy, so a change can't merge a stale blob and
a multi-field change (an import) commits atomically.

**Migration framework ([`settings_migrations.dart`](lib/state/settings_migrations.dart)).**
Identical pattern to [`migrations.dart`](lib/state/migrations.dart):
`SettingsMigration` declares `fromVersion` and `apply(Map<String, dynamic>)`;
`runSettingsMigrations` chains the steps.

**When you change a stored settings shape: append one new `SettingsMigration`
step and bump `currentSettingsVersion` — same rules as game-history migrations.**

**State files:**

| File | Role |
|------|------|
| [`settings_storage.dart`](lib/state/settings_storage.dart) | Load (`loadPersistedSettings`), atomic write (`persistSettings`), bootstrap, error types, `settingsLoadErrorProvider` |
| [`settings_provider.dart`](lib/state/settings_provider.dart) | `SettingsNotifier` — the single in-memory `PersistedSettings` blob; setters + `replaceAll` |
| [`settings_migrations.dart`](lib/state/settings_migrations.dart) | `SettingsMigration` base, `currentSettingsVersion`, registry |
| [`storage_exceptions.dart`](lib/state/storage_exceptions.dart) | Shared persistence-error family: `PersistenceException` base + `UnsupportedVersionException` / `CorruptPersistenceException` (`HasCause`) |
| [`theme_mode_provider.dart`](lib/state/theme_mode_provider.dart) | Read-only `themeMode` view of `settingsProvider` |
| [`default_starter_variant_provider.dart`](lib/state/default_starter_variant_provider.dart) | Read-only `ruleVariants.starterVariant` view |
| [`default_hearts_variant_provider.dart`](lib/state/default_hearts_variant_provider.dart) | Read-only `ruleVariants.heartsVariant` view |

### Backup / export-import ([`backup_codec.dart`](lib/state/backup_codec.dart) + [`export_import_notifier.dart`](lib/state/export_import_notifier.dart))

The export-import subsystem lets users back up both persisted streams (game
history + settings) to a ZIP file and restore them on the same or a different
device. Stored blobs flow through their normal migration runners at import time;
the subsystem adds no extra migration hooks of its own. `currentBackupVersion = 1`
(in `backup_migrations.dart`) versions the ZIP envelope.

**Two layers.** [`backup_codec.dart`](lib/state/backup_codec.dart) is a pure,
dependency-free **format codec** (`BackupCodec.encode` / `BackupCodec.decode`) —
ZIP / manifest / SHA-256 / version structure, with no Riverpod / prefs / platform
state. [`export_import_notifier.dart`](lib/state/export_import_notifier.dart) is
the thin **effectful orchestrator**: `exportBackup` gathers the persisted blobs
(raw prefs reads) and hands them to `BackupCodec.encode`; `ImportNotifier` commits
a decoded backup through the owner providers. The codec delegates each stream's
migrate + validate to that stream's own functions (`runStorageMigrations` +
`validateMigratedGames`, etc.), so it owns *format* logic only.

**ZIP envelope.** `BackupCodec.encode` (via `exportBackup`) writes a ZIP with up
to three entries:

```
manifest.json   {"version":1, "appVersion":"…", "exportedAt":"… (local ISO-8601)",
                 "utcOffset":"+HH:MM", "contains":[…], "hashes":{…}}
games.json      raw SharedPreferencesAsync blob — exactly the {version, games} JSON
settings.json   raw SharedPreferencesAsync blob — exactly the {version, themeMode, …} JSON
```

Each file's SHA-256 is stored in the manifest. Neither blob is transformed —
the import path runs the normal migration runners on them.

**Decode once, commit what was validated.** `BackupCodec.decode(bytes)` is a
**read-only** pass and the **single** validate pass: it decodes, verifies the
manifest + per-stream SHA-256 hashes, runs migrations, runs content validation,
and **keeps the validated objects**. It returns a `DecodedBackup` whose per-stream
`StreamStatus` is a `StreamValid<T>` carrying the parsed payload (the
`List<GameSession>` or the settings map) when importable, or `StreamNotPresent` /
`StreamVersionTooNew` / `StreamCorrupt` otherwise. The import UI holds that
`DecodedBackup` and offers only the `StreamValid` streams.
`ImportNotifier.applyImport(backup, …)` then commits exactly those pre-validated
payloads — it does **not** re-decode or re-validate. The codec stays pure and
synchronous; on the primary native (Android/iOS) targets production runs the
decode off the UI frame through the `decodeBackupProvider` seam (`Isolate.run`),
since the decoded `DecodedBackup` is plain data that transfers back across the
isolate boundary. **Web has no `Isolate.spawn`** — `Isolate.run` throws
`UnsupportedError` there — so the web build decodes inline instead (the 10 MB
input cap keeps that cheap); the seam guards this with `kIsWeb`. Widget tests
override that seam to decode inline (their fake-async clock can't drive a real
isolate). Validation runs once, at the
decode trust boundary; the commit trusts the typed result — the
**validate-at-the-boundary** principle (§2) (a corrupt stream is
`StreamCorrupt`, never importable, so it can't reach a write). The two streams
live under separate SharedPreferencesAsync keys with no cross-key transaction, so the
residual case — a low-level write failure *after* one stream already committed —
is surfaced, not hidden: `applyImport` throws `PartialImportException` carrying
what did commit, and `ImportScreen` tells the user exactly which data was/wasn't
restored. (A failure with nothing committed is surfaced as the original error.)
The commit calls `GameHistoryNotifier.replaceAll()` for games and
`SettingsNotifier.replaceAll()` for settings — the latter a **single atomic
write** of the whole settings blob (never `ref.invalidate` — that would rebuild
from the old startup value; never the three per-field setters, which would leave
settings half-written on a mid-write failure). When games are
replaced, the calculator's pending autosave is cancelled **before** the write (so
it can't resurrect the overwritten session) and the calculator is reset **after**
the write succeeds (so a failed games write leaves any in-progress game intact); a
settings-only import leaves the calculator untouched.

**Zip-bomb / tamper protection** (all in `BackupCodec.decode`): a raw-input-size
check (`_maxBackupFileBytes`, on the actual compressed length, which can't lie)
before decoding; an entry-count cap and an **actual** decompressed-size cap
(`_maxUncompressedBytes`, summing each entry's real decompressed length — not the
attacker-declared header size) after decode; and — once the manifest is trusted —
an entry **allowlist** that rejects any file the manifest does not declare
(`manifest.json` plus one `<stream>.json` per `contains` key). A single entry
crafted to inflate past memory is still bounded only by the 10 MB raw-input cap.

**Validation layers.**
- `lib/models/game_constraints.dart` — pure domain; the single source of the
  *rules*: `kPlayerNameMaxLength` / `kGameNameMaxLength` and predicate/normalizer
  functions (`normalizePlayerName`, `duplicatePlayerNameIndices`,
  `allPlayerNamesFilled`, `normalizeGameName`, …).
- `lib/models/game_invariants.dart` — pure domain; `GameInvariantError` +
  `assertGameInvariants(GameSession)` (engine-level: score sums, per-count value
  bounds, round sequence, counts; name uniqueness via the `game_constraints`
  predicate). Per-stream shape/cardinality (e.g. one recipient per slot) is
  enforced earlier, at parse time, in the model converters (`countsToInput`).
- `lib/state/validation.dart` — `ValidationError`; `validateManifest` (version,
  appVersion, exportedAt, contains, hashes), `validateMigratedGames` (parses each
  game via `GameSession.fromJson`, converting any malformed-JSON throw into a
  `ValidationError` so the codec reports `StreamCorrupt` rather than crashing;
  then calls `assertGameInvariants` + composes the `game_constraints` name/length
  predicates), `validateMigratedSettings`; `validateGameSession` (per-game subset
  of `validateMigratedGames` without the duplicate-id check).

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
- **Import commit** is the deliberate exception: `applyImport` commits the typed
  objects `BackupCodec.decode` already validated and does **not** re-run the
  predicates — validate once at the trust boundary, then trust the result.

**Backup migrations** (`backup_migrations.dart`). Same frozen/sequenced pattern
as `StorageMigration` / `SettingsMigration`. Currently empty (`backupMigrations
= []`, `currentBackupVersion = 1`). Append a `BackupMigration` step here when
the ZIP envelope structure changes (never reorder or remove).

---

## 10. UI layer

**Routing (`main.dart`).** `onGenerateRoute` + `onGenerateInitialRoutes` keep the
start screen at the bottom of the stack — `HomeScreen` normally, `MigrationScreen`
for the legacy app id, or `BootErrorScreen` when the app id could not be read
(`startScreenFor`, see §8). Deep links: `/spelregels` → full rules;
`/spelregels/<gameId>` → that game's rules (so Back returns to the start screen
rather than leaving the app). Locale is forced to Dutch (`nl`); all three
Global*Localizations delegates are registered.

**In-app navigation (`navigation/app_routes.dart`).** Every imperative forward
push — resume/start a game, open settings/export/import/rules, start a new game,
edit a round — goes through `AppRoutes`, a thin layer that owns each
`Navigator.push`/`pushReplacement` and its route options (fullscreen-dialog vs.
card, the rules `ProviderScope` wrapping). It is the only place outside
`main.dart` that maps a destination to a concrete screen, so `lib/widgets` (the
AppBar buttons) can trigger navigation without importing `lib/screens`.

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
  Back-navigation therefore never loses a debounced autosave. The *entry* side
  has a matching single owner: the two callers that transition into a session
  (`HomeScreen`'s session card, `NewGameScreen`'s Start) call
  `holdCalculatorAcrossNavigation(context)` (`calculator_keep_alive.dart`) before
  mutating the notifier and pushing — it holds the autoDispose provider alive
  across the load→navigate gap and releases itself after the next frame, once
  `GameScreen` has subscribed. Because that window is a single frame, both
  callers push **synchronously** — no awaited I/O may sit between the keep-alive
  and the navigation. `NewGameScreen` therefore persists the new game in the
  *background* (after pushing) rather than awaiting `saveGame` first: on mobile a
  `SharedPreferencesAsync` write is a platform-channel round-trip that can span
  frames, which would otherwise drop the keep-alive before `GameScreen` mounts
  and leave `activeSessionProvider`'s cast to throw on `NoSession` (a blank grey
  screen). `_GameSelectionBody`
  separates unplayed and played games per category (negative / positive); played
  games are hidden by default and can be revealed via a per-category toggle in
  `_SectionHeader` — when visible they render disabled ("Spel al gespeeld") and
  offer force-replay on tap. When all games in a category are played and the toggle
  is off, a greyed-out `_AllGamesPlayedCard` fills the otherwise-empty section; it
  hides when the toggle is on (the played tiles themselves provide the content).
  Per-chooser quota disabling and pending-round blocking
  remain as soft disables. Also contains `_LiveScoreboard`, a round-history list,
  and edit-game / delete-game actions. When the game is **finished**, the app bar
  shows a *Deel uitslag* (share) action — the self-contained `ShareResultAction`
  widget (`lib/widgets/`), which owns the whole result-sharing subsystem out of
  the screen: it exports the result as a rendered PNG (an off-screen
  `ShareResultCard`, captured via `RepaintBoundary.toImage`); a popup dialog
  offers an explicit image/text choice and a `CustomSemanticsAction` exposes it
  to assistive tech. Uses `share_plus` (+ `path_provider` for the temp file on
  mobile; the web branch uses `XFile.fromData`). A plain tap shares the image —
  there is **no** app-level image→text fallback: `share_plus` already degrades a
  web browser without the Web Share API to a PNG download. **Feedback contract** (shared with `ExportScreen`): a benign
  cancellation — the user dismissing the share sheet or the save picker — shows
  **nothing** (the share helpers complete normally; `saveFile` returns `false`).
  A genuine failure shows a snackbar: `OutOfSpaceException` → the actionable
  `kOutOfSpaceMessage`, anything else → a generic "mislukt" message. The services
  throw rather than returning a lossy bool, so the UI never has to guess whether
  a non-success meant "cancelled" or "errored".
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
  `rulesEditModeProvider`; the mode (set by the rules route's `ProviderScope` —
  see `AppRoutes.openRules`) controls whether the cog opens the picker
  (`enabled`), is hidden
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

**Theming.** `app_theme.dart` builds the light/dark `ThemeData`; the
`ThemeExtension`s in `app_theme_extensions.dart` supply
warning / suit / double-state / score-sign colors for both brightnesses, and
its `scoreColor` reads them (with a brightness fallback for unthemed
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
  `game_mechanics_test` (dealer/chooser/starter seat math + `doublingTurnIndex`
  turn order + per-chooser quota + `seatIndexOf` throw-on-unknown),
  `score_result_test`.
- **`test/models/`** also has `game_invariants_test.dart` —
  `assertGameInvariants` happy path + each invariant violation — and
  `game_constraints_test.dart` (the shared name predicates/normalizers).
- **`test/state/`** — `calculator_provider_test`, `game_history_provider_test`
  (incl. migration, corrupt data, unsupported-version handling, and
  `CorruptPersistenceException` end-to-end for dangling player-id references),
  `validation_test` (`validateManifest` / `validateMigratedGames` /
  `validateMigratedSettings`), `export_import_test` (`exportBackup` round-trip,
  hash verification, `analyzeBackup` valid/corrupt/version/stream errors,
  zip-bomb guard), `apply_import_test` (`replaceAll`, `applyImport` full
  round-trip, games-only, settings-only live update, pending round,
  no-partial-write guard).
- **`test/main_test.dart`** — bootstrap routing policy: `startScreenFor`
  (normal → `HomeScreen`, legacy → `MigrationScreen`, unresolved →
  `BootErrorScreen`) and the `routeWidgetFor` deep-link grammar, plus the
  boot-failure branch via `BonkenApp(isLegacyApp: null)`.
- **`test/widgets/`** — one file per screen/widget.
- **`test/data/`** — `game_rules_test.dart`: variant coverage + coupling test
  (every `kGameSections.gameId` exists in `allGames`).
- **`test/tool/`** — pure-logic tests for the `tool/` helper libraries
  (`semver`, `pubspec_yaml`, `pubspec_lock`, `google_fonts_parser`,
  `flutter_release`, `gha_pins` — action/Ubuntu-runner pin parsing + bumping —,
  `fastlane_pin`). No network, no subprocess — only the extracted helpers.
- **Guards:** `architecture_test.dart` source-scans `lib/` and fails the build on
  any of: a raw `Scaffold` instead of `AppScaffold` (anywhere, not just
  `lib/screens`); a direct `showModalBottomSheet`/`showSnackBar` instead of the
  `showAppBottomSheet`/`showTimedSnackBar` wrappers; a legacy `Icons.*` reference
  (Symbols-only); a `lib/models` file importing Flutter UI (bar the IconData
  exception) or up-importing into the state/UI layers; a `lib/state`/`lib/services`
  file importing `lib/{screens,widgets,theme}`; or a screen under `lib/screens`
  not pumped in `test/a11y_test.dart`.
  `license_assets_test.dart` verifies: all four bundled font `.ttf` files appear
  in the asset manifest (drift guard for `google_fonts` version bumps); the Arimo
  SIL OFL entry appears in `LicenseRegistry` (compliance gate); the
  `Arimo-LICENSE.txt` asset resolves at runtime; and the root AGPL `LICENSE`
  asset resolves; `a11y_test.dart` pumps every
  screen and gates `textContrastGuideline`, `labeledTapTargetGuideline`, and
  `android`/`iOSTapTargetGuideline` (see §2 for the full a11y posture).

**Shared helpers** ([`test/test_helpers.dart`](test/test_helpers.dart)):
`setUpPrefs([initial])` installs a fresh in-memory `SharedPreferencesAsync`
backend (the API the storage layer uses) per test; `setAsyncPrefs([data])` is the
mid-test reseed; `initializeWidgets()` ensures the binding.

**Conventions to know:**
- Seed prefs with `setUpPrefs({...})` / `setAsyncPrefs({...})` (the async store).
  The legacy `SharedPreferences.setMockInitialValues({...})` seeds only the *old*
  store and is used solely by `prefs_async_migration_test.dart` to drive the
  one-off legacy→async move (§9).
- The **autosave debounce** (400 ms), the **snackbar** auto-dismiss timer, and
  the **Riverpod retry** (~200 ms) all leave pending timers that must be
  **drained** (`await tester.pump(Duration(...))` / `pumpAndSettle`) or teardown
  fails. See `game_screen_actions_test.dart` and the `drainRetry` helper in
  `game_history_provider_test.dart`.
- `showTimedSnackBar` hides any current bar before showing the next, so two
  deletes in sequence leave only the **one** remaining framework auto-dismiss
  timer (`persist: false`) to drain. The framework cancels that timer on any
  hide (close icon, swipe, the undo action, or a replacing bar), so testing the
  undo action by **tapping the widget** is safe — hiding the bar cancels the
  timer, leaving none to drain and no second `close` on an already-gone bar.
- Construct fixtures with real model objects (e.g. `const Dominoes()`,
  `RoundRecord(...)`), not hand-rolled JSON, so they stay in sync with the code.
- **Platform side-effects are injected via providers, never via test-only
  constructor params.** The share sheet and file picker are reached through
  `shareFileProvider` / `shareTextProvider` / `pickBackupBytesProvider`
  ([`platform_io_providers.dart`](lib/state/platform_io_providers.dart), thin
  wrappers over [`share_service.dart`](lib/services/share_service.dart) /
  [`file_pick_service.dart`](lib/services/file_pick_service.dart)). Tests swap
  them with `ProviderScope.overrides` / `ProviderContainer(overrides: …)` to
  drive the share / save / file-pick flows. Tests simulate failures by having the
  override **throw** — `OutOfSpaceException` for the user-fixable out-of-space
  case, anything else for a generic failure — mirroring the real services'
  contract (see §10). **Do not** inject test behaviour through
  `@visibleForTesting` constructor params or runtime debug branches — that ships
  a never-taken branch and a test-only API in the production widget.
  (`@visibleForTesting` on a *pure function that production also calls* is fine —
  it only relaxes visibility, adds no runtime branch.) Note `ShareResultAction`'s
  real PNG capture (`_captureShareCard`, plus the asset precache) is left
  un-mocked rather than seamed and is real-async, so its image path isn't
  widget-tested — its failure handling mirrors the export path that is, and the
  default-tap path is covered only by the screen-reader custom actions.
  `ShareResultAction`'s clipboard write (`_copyText`) is likewise an intentional
  exception to the provider-seam rule: `Clipboard.setData` is auto-mocked by the
  test binding, so it stays testable without a seam, and a failure surfaces the
  same snackbar as the share/save actions (via the shared `_runIo` catch).

---

## 12. Build, run & release

Flutter SDK version is pinned in [`.fvmrc`](.fvmrc). CI installs it from there
via the `setup-build` action. Always use `fvm flutter`/`fvm dart` locally to run
against the pinned version. Bump the pin to the latest **stable** release with
`fvm dart run tool/update_flutter.dart` — it rewrites `.fvmrc`, the `pubspec.yaml`
Dart `sdk:` lower-bound, the Android toolchain versions, and the iOS deployment
target together, then runs `fvm install`. Exits without writing when already
current (`--force` re-runs `fvm install` + the native-toolchain sync anyway;
[`--check`](tool/update_flutter.dart) reports without writing). Never downgrades
if the pin is ahead of stable.

Android `minSdk` floats with the Flutter SDK (`flutter.minSdkVersion`), so it
needs no sync. iOS has no such auto-float, so the tool reads Flutter's own
minimum iOS deployment target (the value a fresh `flutter create` uses, from the
SDK's iOS app template) and raises `IPHONEOS_DEPLOYMENT_TARGET` in
`ios/Runner.xcodeproj/project.pbxproj` **only** when Flutter's floor rises above
the project's — it is never lowered. The project currently pins **14.0**, above
Flutter 3.44's own 13.0 minimum, because the **`file_picker` Swift Package
requires iOS 14.0** (an SPM build otherwise fails with "the package product
'file-picker' requires minimum platform version 14.0 … but this target supports
13.0"; iOS uses SPM here, not CocoaPods, so the target is the three
`project.pbxproj` lines). That package-driven floor is maintained by hand — the
tool tracks only Flutter's baseline minimum, so it correctly leaves 14.0 in
place and never lowers it back into a broken build. A future `file_picker` (or
other plugin) bump can raise the floor again; that surfaces as a build error and
is bumped manually, the same way 14.0 was. See the `file_picker` note below.

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

The [`verify`](.github/actions/verify/action.yml) composite action (run by every
workflow that validates or ships the app — PRs and the build-producing push/release
workflows) enforces **three** gates in order:
`dart format --output=none --set-exit-if-changed .`, `flutter analyze --fatal-infos`,
and `flutter test`. Run all three locally before pushing. **Coding agents:** also
run `fvm dart format .` — formatting drift fails CI just like an analyzer error.

`dart fix --dry-run` is also part of `verify` — CI fails if the analyzer proposes
any auto-fix. Run `fvm dart fix --apply` locally to clear drift before pushing.

`verify`'s final step runs the **OSV vulnerability scanner**
(`google/osv-scanner-action`, scanning `pubspec.lock`). Each workflow that runs
`verify` therefore grants `security-events: write`
at the workflow level: the scanner uploads its findings as SARIF to the
repository's Security tab, which needs that permission. It is declared on each
caller workflow rather than inside the `verify` composite action because a
composite action cannot scope the calling job's token — so the permission is a
deliberate, documented part of the workflows that invoke the scan, not an
over-broad grant.

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
on a macOS runner). The Android upload lands in the Play Console alpha
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

There is deliberately **no committed `Gemfile.lock`** (in either `android/` or
`ios/`). fastlane runs only in the pipeline — each job resolves the bundle fresh
under `~> 2` via `ruby/setup-ruby`'s `bundler-cache` — and is never run locally,
so a lockfile would add Ruby + Bundler as local-dev dependencies and a recurring
update chore for no gain. The `~> 2` major ceiling is the intended
reproducibility boundary; do not add a lockfile.

### GitHub Actions & runners

Actions are pinned either to a major tag (`@v6`) or, for actions without a moving
`vN` (e.g. the OSV scanner), to a specific version (`@v2.3.8`). Runner images are
likewise pinned to a specific version in each job's `runs-on` (Linux for the
build/test jobs, macOS for the iOS jobs), so CI stays reproducible and a new image
— including the Xcode the macOS image bundles — is adopted deliberately rather
than silently.

`fvm dart run tool/update_gha.dart` checks the whole CI toolchain in one pass: it
bumps any out-of-date **action** in place — to the newest major for major pins,
the newest `vX.Y.Z` for version pins, including subdirectory actions (`--check`
only reports) — and **reports** (never changes) when a newer **Ubuntu LTS runner**
image or **fastlane major** is available, since those bumps are deliberate (a
fastlane major may need Fastfile edits; a new Ubuntu image can rename packages).
The macOS pin is not tracked by the tool — it is bumped by hand. Set
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
(config in `pubspec.yaml`), and generates all platform splash images and PWA maskable icons.
Requires `rsvg-convert` (`apt install librsvg2-bin`) and `fc-match`/`fc-query`
(`apt install fontconfig`); CI installs both in `setup-build`. Locally the script
requires `fvm`; CI passes `--ci` so it uses PATH `dart` directly. Do not run
`fvm dart run flutter_launcher_icons` directly: it skips the intermediate source PNGs,
the maskable PWA icon override, all splash-screen generation, and the font-sandbox sanity check.

**Font sandbox:** the script sets two env vars to guarantee consistent rendering on
both Linux and macOS:

- `FONTCONFIG_FILE` points to a throwaway config exposing *only* `assets/google_fonts/<version>/`,
  so suit/word glyphs rasterise from the same `.ttf`s the app ships (no system-font drift).
- `PANGOCAIRO_BACKEND=fontconfig` forces Pango's FreeType backend. On macOS, Pango defaults to
  CoreText, which bypasses `FONTCONFIG_FILE` entirely and causes rsvg-convert to fall back to
  Apple Symbols for suit glyphs — wrong shapes and wider spacing. On Linux this var is a no-op.

The sanity check is **asset-driven**: every bundled `.ttf` must resolve, through the sandbox,
back to itself. That stays exhaustive as font cuts change, but it deliberately does **not** verify
that the families the SVGs *reference* are bundled — so a future SVG naming an unbundled
family/weight would silently fall back rather than error. Today the SVGs reference only `Roboto`
and `Arimo` at weight 400, both bundled; keep new SVG glyphs within the shipped cuts.

**SVG sources** — two card sizes are in use, driven by platform constraints:

*62.5 % card* (viewBox `0 0 1024 1024`): `icon_bonken.svg` (gradient background)
and `icon_bonken_flat.svg` (solid `#283593` background). iOS only rounds corners —
no circle mask — so no safe-zone padding is needed and the card can fill more of
the canvas.

*50 % card* (viewBox `−128 −128 1280 1280`): `icon_bonken_adaptive_fg.svg`
(transparent — Android adaptive foreground, all native splash images) and
`icon_bonken_padded.svg` (radial gradient background — PWA maskable icons and legacy
Android launcher fallback) and `icon_bonken_adaptive_bg.svg` (gradient background
layer only, for the Android adaptive background drawable). The extra padding vs. the
62.5 % card is required for Android's strict-circle launcher mask; see **Safe-zone
calibration** below. This size is also used for all native splash screens, so the
native splash card appears visually consistent with the PWA splash even though the
launcher icon is larger on iOS.

The card coordinates, radii, and suit positions are **identical** in all five SVGs;
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
  (gradient, 50 % card — `image_path` in `pubspec.yaml`).
  `android:inset="10%"` on the foreground; see **Safe-zone calibration** below.
- *Android PWA*: `flutter_launcher_icons` (`web.generate: true`) generates
  `Icon-192.png` and `Icon-512.png` from `icon_bonken.png` (62.5 % card, gradient)
  and an initial `Icon-maskable-{192,512}.png`; `generate_icons.sh` then overwrites
  the maskable variants from `icon_bonken_padded.svg` (50 % card, gradient). This
  split is necessary because `flutter_launcher_icons` has no separate `maskable_image_path`
  for web. `flutter_launcher_icons` also merges `background_color`, `theme_color`, and
  the `icons` array into `manifest.json` (non-icon fields are preserved).

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
  `windowSplashScreenBackground` (`#283593`) and `windowSplashScreenAnimatedIcon`
  (`@drawable/splash_logo` — the same transparent card as API 21–30). Without the
  explicit icon, API 31+ auto-uses the full adaptive launcher icon including its
  gradient circle, which is visually inconsistent with the flat-indigo splash on
  older API levels. `windowSplashScreenIconBackgroundColor` is intentionally absent:
  setting it draws an elevated circle with a material shadow even when the colour
  matches the screen background, creating a visible ring around the icon.
- *Android PWA*: Chrome auto-generates a splash from `background_color: "#283593"`
  in `manifest.json` and the best-matching manifest icon (maskable, clipped to a
  squircle). The maskable icons use `icon_bonken_padded.svg` (gradient background),
  which produces a visible gradient halo at the squircle clip boundary — this is an
  accepted tradeoff. A transparent maskable icon was tried first but caused a black
  squircle on splash (Chrome does not initialise the splash canvas with `background_color`
  before compositing the masked icon; transparent pixels render black).
- *Web (HTML loading screen)*: `index.html` shows a `#283593` full-screen div with
  `Icon-192.png` at 96 × 96 px CSS (62.5 % card, gradient background — generated by
  `flutter_launcher_icons` from `icon_bonken.png`) and an animated progress bar; the
  div fades out on `flutter-first-frame`. This runs during JS/Flutter download inside
  the browser tab and is distinct from the PWA splash — it appears for both
  installed-PWA and plain-browser visits.

**Safe-zone calibration:** `icon_bonken_adaptive_fg.svg` and `icon_bonken_padded.svg`
both use viewBox `−128 −128 1280 1280` (card at 50 % of canvas). The native
`android:inset="10%"` (`adaptive_icon_foreground_inset` in `pubspec.yaml`) shrinks the
foreground to 80 % of the 108 dp canvas, so adaptive corners are ~8–10 px inside the
36 dp safe zone (at 3–4× DPI). The PWA maskable corners are ~7 px inside the
40 %×1280 = 512 SVG-unit safe zone on the 512 px icon file. If
`adaptive_icon_foreground_inset` or the card geometry changes, recalculate both margins.

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

`icon_bonken.svg` (gradient) also serves as the Play Store listing icon.

The **squircle icon** has its own SVG source, `icon_bonken_squircle.svg` — the
same card geometry as `icon_bonken.svg` but with rounded background corners so it
reads as a self-contained app icon rather than a hard-edged square. It is the
source for two pre-sized renders (`generate_icons.sh`), both rendered at their
exact display size so Flutter never resizes at runtime:

- **About-dialog icon** — `icon_bonken_about.png` at the 48 dp display size with
  `2.0x/3.0x` resolution variants (96 / 144 px), listed as a 1x asset in
  `pubspec.yaml`. Flutter picks the variant matching `devicePixelRatio`, so the
  header icon renders 1:1 — previously it downscaled the 1024 px launcher PNG
  ~21× and looked soft.
- **Share-card icon** — `icon_bonken_share.png` at 72 px (3× its 24 dp display
  size in `ShareResultCard`). The baked-in squircle corners replace the former
  runtime `ClipRRect`.

**Corner ratio (single source of truth): 22.37 %.** This is a rounded-rect
approximation of the iOS app-icon squircle — a continuous superellipse in
reality — and doubles as a reasonable Android rounded-square mask; it is *not*
two separate platform standards. The same 22.37 % is used everywhere the app
rounds its own icon, and the two literals must be kept in sync:

- `rx`/`ry` on the background rect in `icon_bonken_squircle.svg` (covers the
  About-dialog + share-card icons, baked in at generation time), and
- `border-radius` on the splash `#loading img` in `web/index.html`. The web
  splash keeps the rounding in **CSS** (not a baked asset) on purpose: it's a
  resolution-independent vector clip — no downscaling to fix, unlike the Flutter
  raster icons — and `border-radius` is what drives the icon's `box-shadow`.

### Store badges

The About dialog (web only, via `StoreBadges` in `app_bar_widgets.dart`) and the
README link to the native builds with the **official** store badge artwork in
`assets/store/`:

- **App Store** — `app_store_badge_nl.png`: Apple's "Download on the App Store"
  badge, **black** style, **Dutch** (`nl-nl`) locale, from the Apple Marketing
  Toolbox (`toolbox.marketingtools.apple.com/.../download-on-the-app-store/black/nl-nl`).
  Apple ships it as SVG, rendered to PNG with `rsvg-convert` (the app bundles no SVG
  renderer — `flutter_svg` is intentionally not a dependency).
- **Google Play** — `google_play_badge_nl.png`: Google's "Ontdek het op Google
  Play" web-generic badge, **Dutch** (`nl`) locale — the official PNG from
  `play.google.com/intl/.../badges/nl_badge_web_generic.png` (Google publishes no
  SVG). Its built-in transparent vertical padding is trimmed first so it aligns
  with the tight App Store badge at equal display height.

**Sizing — pre-sized, no runtime resize.** Both badges are rendered to the exact
display height (`_storeBadgeHeight`, 56 logical px) with `2.0x/` and `3.0x/`
resolution variants (112 / 168 px tall) under `assets/store/`. Listing the 1x
files in `pubspec.yaml` makes Flutter auto-pick the variant matching the device's
`devicePixelRatio`, so the badge (which contains fine wordmark text) renders 1:1
with no runtime downscaling — a high-res single asset shrunk at runtime looked
mushy on 1x displays. The README points at the `3.0x/` files so browsers downscale
the high-res copy crisply at any DPR. If `_storeBadgeHeight` changes, regenerate
all three sizes (Apple from the SVG, Google by Lanczos-downscaling the trimmed PNG).

Unlike the launcher icons (SVG sources → PNGs generated by `generate_icons.sh` and
gitignored), these badge PNGs are **committed** as vendored third-party artwork:
they aren't derived from our SVGs, and Google ships no vector, so there's nothing
to regenerate them from offline. They are the only committed PNGs in the repo.

Both are the Dutch badges — the app's only language, and the store wordmark is part
of the artwork, so there is no locale-neutral badge. To localise for another
language, fetch the same badges for that locale (Apple Toolbox `/{locale}`, Google
`{locale}_badge_web_generic.png`) and pick by locale in `StoreBadges`; the listing
URLs themselves are locale-agnostic.

### Store screenshots

Run `fvm dart tool/generate_screenshots.dart` with `--android <phone|tablet|all>`
or `--ios <iphone|ipad|all>` (iOS requires Xcode) to take store screenshots. It
uses Flutter's `integration_test` SDK package with `flutter drive`: the integration
test (`integration_test/screenshot_test.dart`) navigates the app to each UI state
and signals the host driver (`test_driver/screenshot_driver.dart`) via stdout
markers; the driver captures the full device screen via `adb exec-out screencap`
(Android) or `xcrun simctl io … screenshot` (iOS) and writes to
`screenshots/<platform>_<device-type>_<name>.png` (e.g. `android_phone_01_home.png`).
A failed or incomplete run fails the job through `flutter drive`'s exit code, and
the host throws on non-zero — so the artifact is only ever uploaded when the full
set was produced. This works because each `SCREENSHOT:` marker blocks the test
until the host has captured and ack'd it: a missing capture stalls the test into a
failure, which the `integration_test` driver reports as a non-zero exit.

Each of the two `testWidgets` sessions boots the app on an empty store, then
seeds its games by importing the fixture
(`integration_test/screenshot_fixtures.dart`) through the app's real import
pipeline (`BackupCodec.encode` → `decode` → `ImportNotifier.applyImport`) —
session A covers the home, new-game, and final-score screens; session B covers the
round-input screens and the rules page. Importing sets the in-memory state
directly, so the rendered data can't be clobbered by DataStore read caching or the
legacy→async migration racing the first boot read (writing SharedPreferences
before `main()` was subject to both); it also runs the storage migrations on the
fixture, so one written at an older `version` is migrated up rather than needing a
hand-bump on every schema change. `test/integration_screenshot_fixtures_test.dart`
runs the fixtures through that same decode→migrate→validate path in the regular
suite, so drift fails there instead of only on-device. All device and locale
config is declared as consts inside the script itself; `--print-env` outputs the
Android values as `KEY=VALUE` lines for CI.

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
pre-release. It is the cross-platform picker for importing backup ZIPs. It also
sets the project's iOS floor: `file_picker`'s iOS Swift Package requires iOS
14.0, which is why `IPHONEOS_DEPLOYMENT_TARGET` is 14.0 (see §12) — dropping or
replacing this plugin is the only thing that could lower it.

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
  re-derive "dealer = chooser − 1", "chooser = dealer + 1", "starter = …", or the
  doubling turn order elsewhere. This includes `chooserIndexFor` (inverse of
  `dealerIndexFor`), `starterIndexFor` (takes a `StarterVariant`), and
  `doublingTurnIndex` — all live here. (The `List<Player>` lookup/rotation helpers
  `seatIndexOf` / `rotatedFromDealer` are not relationship math and live with
  `Player` in `player.dart`.)
- **Screens use `AppScaffold`** (architecture test enforces it).
- **Bottom sheets use `showAppBottomSheet`**, never `showModalBottomSheet`
  directly (architecture test enforces it).
- **Icons are `Symbols.*` only** — never the legacy `Icons`.
- **`gameById` and `seatIndexOf` throw on an unknown id** — never rely on a
  silent fallback. An unknown id from stored JSON is caught at the load boundary
  (`GameSession.fromJson` calls `_validateReferences`; any throw becomes
  `CorruptPersistenceException` via `GameHistoryNotifier.build()`'s `on Object`
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
  does this automatically; hand-written cards add it explicitly. Review-enforced,
  not gated: no built-in a11y guideline can inspect header flags (§2).
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
Heren/Boeren=Kings/Jacks, Vrouwen=Queens, Bukken=Duck, Hartenpunten=Heart
points, 7e/13e=7th/13th trick, Laatste slag=Final trick, Domino=Dominoes.
