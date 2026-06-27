import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import '../screens/edit_game_screen.dart';
import '../screens/export_screen.dart';
import '../screens/game_screen.dart';
import '../screens/import_screen.dart';
import '../screens/new_game_screen.dart';
import '../screens/round_input_screen.dart';
import '../screens/rules_screen.dart';
import '../screens/settings_screen.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import '../state/rules_edit_mode_provider.dart';

/// Centralised in-app navigation: every imperative screen push goes through one
/// of these helpers instead of constructing a [MaterialPageRoute] inline. It
/// keeps the route-construction details — fullscreen-dialog vs. card, push vs.
/// replace, the rules [ProviderScope] wrapping — in one place, and lets
/// `lib/widgets` trigger navigation (the AppBar buttons) without importing
/// `lib/screens` directly. This is the only file that knows which concrete
/// screen each destination maps to.
///
/// The deep-link/named-route factory (`/spelregels`, the legacy migration
/// screen) lives separately in `main.dart`'s `onGenerateRoute`; this layer is
/// only for the imperative `Navigator.push` calls made from within the app.
abstract final class AppRoutes {
  /// New-game flow, as a fullscreen dialog (a modal "create" surface).
  static Future<void> openNewGame(BuildContext context) =>
      _push(context, const NewGameScreen(), fullscreenDialog: true);

  /// In-game hub for an already-selected/loaded session.
  static Future<void> openGame(BuildContext context) =>
      _push(context, const GameScreen());

  /// Replaces the current route (the new-game flow) with the in-game hub after
  /// "Start spel", so Back from the game returns to Home rather than to the
  /// now-committed setup screen.
  static Future<void> replaceWithGame(BuildContext context) =>
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => const GameScreen()),
      );

  /// Per-round score entry. Pass [fullscreenDialog] when editing an existing
  /// round (a modal edit surface); the resume/select-game path uses the default
  /// card transition.
  static Future<void> openRoundInput(
    BuildContext context, {
    bool fullscreenDialog = false,
  }) => _push(
    context,
    const RoundInputScreen(),
    fullscreenDialog: fullscreenDialog,
  );

  /// Edit players / first dealer / variants for the current session, as a
  /// fullscreen dialog.
  static Future<void> openEditGame(BuildContext context) =>
      _push(context, const EditGameScreen(), fullscreenDialog: true);

  /// Backup export flow.
  static Future<void> openExport(BuildContext context) =>
      _push(context, const ExportScreen());

  /// Backup import flow.
  static Future<void> openImport(BuildContext context) =>
      _push(context, const ImportScreen());

  /// App-wide settings.
  static Future<void> openSettings(BuildContext context) =>
      _push(context, const SettingsScreen());

  /// Rules document (full, or scoped to [singleGameId]).
  ///
  /// When [starterVariantOverride] / [heartsVariantOverride] are given, the
  /// pushed route is wrapped in a [ProviderScope] that locks the rules to those
  /// session values: the pushed subtree is fresh, so the session's variants are
  /// injected via overrides scoped to it (rather than threaded through every
  /// rules widget) and resolve to the session values for the lifetime of this
  /// route only. [editMode] controls whether variant-sensitive blocks expose
  /// the settings cog.
  static Future<void> openRules(
    BuildContext context, {
    String? singleGameId,
    StarterVariant? starterVariantOverride,
    HeartsVariant? heartsVariantOverride,
    RulesEditMode editMode = RulesEditMode.enabled,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ProviderScope(
        overrides: [
          if (starterVariantOverride != null)
            defaultStarterVariantProvider.overrideWithValue(
              starterVariantOverride,
            ),
          if (heartsVariantOverride != null)
            defaultHeartsVariantProvider.overrideWithValue(
              heartsVariantOverride,
            ),
          rulesEditModeProvider.overrideWithValue(editMode),
        ],
        child: RulesScreen(singleGameId: singleGameId),
      ),
    ),
  );

  static Future<void> _push(
    BuildContext context,
    Widget screen, {
    bool fullscreenDialog = false,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => screen,
      fullscreenDialog: fullscreenDialog,
    ),
  );
}
