import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_version.dart';
import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import '../screens/rules_screen.dart';
import '../screens/settings_screen.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import '../state/rules_edit_mode_provider.dart';
import '../state/theme_mode_provider.dart';
import '../utils.dart';

/// Small, reusable AppBar building blocks shared across the app's
/// screens: the [AboutIconButton] leading, the per-screen
/// [TitleWithRules] (which embeds a [RulesIconButton] next to the
/// title), and the [ThemeMenuButton] used as a trailing action on the
/// home screen. Keeping them in one place ensures every screen's
/// AppBar stays visually consistent.

/// GitHub repository URL shown as a link in the About dialog.
const _aboutRepoUrl = 'https://github.com/SunMar/bonken';

/// Privacy policy URL shown as a link in the About dialog.
const _aboutPrivacyUrl = 'https://sunmar.github.io/bonken/privacy.html';

/// Compile-time commit hash injected by the deploy-to-Pages workflow.
/// Empty for local / store builds. Consumed by [resolveAppVersion], which feeds
/// both the About dialog and the export manifest — hence not About-specific.
@visibleForTesting
const gitCommit = String.fromEnvironment('GIT_COMMIT');

/// Asset path of the launcher icon shown in the About dialog header.
const _aboutIconAsset = 'assets/icon/icon_bonken.png';

/// Theme-mode entries for the "Thema" menu (single source of truth).
const _themeModeEntries = <(ThemeMode, IconData, String)>[
  (ThemeMode.system, Symbols.contrast, 'Systeem'),
  (ThemeMode.light, Symbols.light_mode, 'Licht'),
  (ThemeMode.dark, Symbols.dark_mode, 'Donker'),
];

/// Leading AppBar icon that opens the About dialog. Used on the home
/// screen (which has no back button). The game screen omits this in
/// favour of the auto-inserted back button.
class AboutIconButton extends StatelessWidget {
  const AboutIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Symbols.info),
      tooltip: 'Over Bonken',
      onPressed: () => openAboutDialog(context),
    );
  }
}

/// AppBar icon that pushes the [RulesScreen]. By default opens the
/// full rule book; pass [singleGameId] to scope it to one mini-game.
///
/// When [starterVariantOverride] / [heartsVariantOverride] are set, the pushed
/// route is wrapped in a [ProviderScope] that locks the rules to those
/// session values: variant-sensitive blocks show only the active text and hide
/// the settings icon / "Spelregel variant" alternative. Pass them when opening
/// rules from within a game.
class RulesIconButton extends StatelessWidget {
  const RulesIconButton({
    super.key,
    this.singleGameId,
    this.tooltip,
    this.starterVariantOverride,
    this.heartsVariantOverride,
    this.editMode = RulesEditMode.enabled,
  });

  /// When set, the pushed [RulesScreen] only shows this game's rules.
  final String? singleGameId;

  /// Overrides the default 'Spelregels' tooltip (useful when the icon
  /// is scoped to a specific game).
  final String? tooltip;

  final StarterVariant? starterVariantOverride;
  final HeartsVariant? heartsVariantOverride;

  /// Controls how variant-sensitive blocks behave in the pushed [RulesScreen].
  /// See [RulesEditMode] for the three modes.
  final RulesEditMode editMode;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Symbols.menu_book),
      tooltip: tooltip ?? 'Spelregels',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          // The pushed route is a fresh subtree, so the session's variants are
          // injected via provider overrides scoped to it (rather than threaded
          // through every rules widget). The overridden "default" providers
          // resolve to the session values for the lifetime of this route only.
          builder: (_) => ProviderScope(
            overrides: [
              if (starterVariantOverride != null)
                defaultStarterVariantProvider.overrideWith(
                  () => DefaultStarterVariantNotifier(
                    initialVariant: starterVariantOverride!,
                  ),
                ),
              if (heartsVariantOverride != null)
                defaultHeartsVariantProvider.overrideWith(
                  () => DefaultHeartsVariantNotifier(
                    initialVariant: heartsVariantOverride!,
                  ),
                ),
              rulesEditModeProvider.overrideWithValue(editMode),
            ],
            child: RulesScreen(singleGameId: singleGameId),
          ),
        ),
      ),
    );
  }
}

/// AppBar `title:` widget that places a [RulesIconButton] right after
/// the screen's title text. Used on every screen that has rules to
/// surface — keeps the spacing, icon density and tap-target rules
/// consistent.
///
/// The trailing icon is rendered with zero padding so it sits tight
/// against the title without pushing the text off its baseline, while
/// keeping the standard 48dp tap target (no density shrink) for a11y.
class TitleWithRules extends StatelessWidget {
  const TitleWithRules({
    super.key,
    required this.title,
    this.singleGameId,
    this.tooltip,
    this.flexibleTitle = false,
    this.starterVariantOverride,
    this.heartsVariantOverride,
    this.editMode = RulesEditMode.enabled,
  });

  /// The title text (or any widget). Wrap arbitrarily-long titles
  /// with [flexibleTitle] so they can ellipsise.
  final Widget title;

  /// Forwarded to [RulesIconButton.singleGameId].
  final String? singleGameId;

  /// Forwarded to [RulesIconButton.tooltip].
  final String? tooltip;

  /// When `true`, wraps [title] in a [Flexible] so long titles
  /// ellipsise instead of overflowing the AppBar.
  final bool flexibleTitle;

  /// Forwarded to [RulesIconButton] — see its doc for semantics.
  final StarterVariant? starterVariantOverride;

  /// Forwarded to [RulesIconButton] — see its doc for semantics.
  final HeartsVariant? heartsVariantOverride;

  /// Forwarded to [RulesIconButton] — see its doc for semantics.
  final RulesEditMode editMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        flexibleTitle ? Flexible(child: title) : title,
        const SizedBox(width: 4),
        IconButtonTheme(
          data: const IconButtonThemeData(
            style: ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
            ),
          ),
          child: RulesIconButton(
            singleGameId: singleGameId,
            tooltip: tooltip,
            starterVariantOverride: starterVariantOverride,
            heartsVariantOverride: heartsVariantOverride,
            editMode: editMode,
          ),
        ),
      ],
    );
  }
}

/// AppBar action that pushes [SettingsScreen] onto the navigator.
class SettingsIconButton extends StatelessWidget {
  const SettingsIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Symbols.settings),
      tooltip: 'Instellingen',
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
    );
  }
}

/// AppBar action that opens a small [MenuAnchor] with the three theme
/// modes. The currently-active mode is marked with a trailing check.
class ThemeMenuButton extends ConsumerWidget {
  const ThemeMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    // MenuAnchor pinned `bottomEnd`: the menu's top-left lands at the
    // IconButton's bottom-right corner, dropping the menu below the
    // button. Without this, M3's default `topEnd` would make the menu
    // overlap the button vertically.
    return MenuAnchor(
      style: const MenuStyle(alignment: AlignmentDirectional.bottomEnd),
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Symbols.contrast),
        tooltip: 'Thema',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        for (final (value, glyph, label) in _themeModeEntries)
          MenuItemButton(
            style: kMenuItemButtonStyle,
            leadingIcon: Icon(glyph),
            trailingIcon: value == mode
                ? const Icon(Symbols.check, size: 16)
                : null,
            onPressed: () =>
                ref.read(themeModeProvider.notifier).setMode(value),
            child: Text(label),
          ),
      ],
    );
  }
}

/// Opens the stock Material [showAboutDialog] populated with the app
/// icon, version line and a link to the GitHub repository. The dialog's
/// built-in "View licenses" footer button pushes the licence page
/// registered in `lib/main.dart`.
Future<void> openAboutDialog(BuildContext context) async {
  final versionLine = await resolveAboutVersionLine();
  if (!context.mounted) return;
  showAboutDialog(
    context: context,
    applicationName: 'Bonken',
    applicationVersion: versionLine,
    applicationIcon: Image.asset(_aboutIconAsset, width: 48, height: 48),
    children: [
      _AboutLink(
        icon: Symbols.code,
        label: 'Broncode',
        onTap: () async {
          final uri = Uri.parse(_aboutRepoUrl);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
      ),
      _AboutLink(
        icon: Symbols.privacy_tip,
        label: 'Privacybeleid',
        onTap: () async {
          final uri = Uri.parse(_aboutPrivacyUrl);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
      ),
    ],
  );
}

/// Returns the resolved app version for embedding in exports and the About
/// dialog. Returns `null` for dev/profile builds where no meaningful version
/// exists. The record's [buildNumber] is `null` when not applicable (e.g.
/// web CI builds where the commit hash is the identifier).
///
/// Both [resolveAboutVersionLine] and the export path call this so they
/// always agree on what "the current version" is.
AppVersion resolveAppVersion(PackageInfo info) {
  if (kDebugMode || kProfileMode) return const AppVersion();
  if (gitCommit.isNotEmpty) {
    return const AppVersion(version: gitCommit);
  }
  return AppVersion(
    version: info.version == '0.0.0' ? null : info.version,
    buildNumber: info.buildNumber.isEmpty ? null : info.buildNumber,
  );
}

/// Resolves the human-readable version string shown in the About dialog.
///
/// Delegates version derivation to [resolveAppVersion] so the about dialog
/// and the export manifest always agree on what "the current version" is.
///
/// Pure (no [BuildContext], no widget pumping) so it can be unit-tested
/// directly.
@visibleForTesting
Future<String> resolveAboutVersionLine() async {
  // Early-return before the async platform call so tests (which run in debug
  // mode) never hit PackageInfo.fromPlatform(), which has no platform host.
  if (kDebugMode || kProfileMode) return 'Ontwikkelversie';
  try {
    final info = await PackageInfo.fromPlatform();
    final v = resolveAppVersion(info);
    final version = v.version;
    if (version == null) return 'Versie onbekend';
    final build = v.buildNumber;
    if (build != null) return 'Versie $version (build $build)';
    // No build number: git-commit build — show the hash.
    return 'Commit $version';
  } on Exception catch (_) {
    return 'Versie onbekend';
  }
}

/// Underlined icon+text link used inside the About dialog.
///
/// Implemented as a [TextButton.icon] (rather than a bare [InkWell])
/// so it picks up Material 3's default [MaterialTapTargetSize.padded]
/// behaviour for free — the visual chrome is small but the tap target
/// reaches [kMinInteractiveDimension] (48 dp).
class _AboutLink extends StatelessWidget {
  const _AboutLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      hint: 'Opent in browser',
      child: TextButton.icon(
        style: const ButtonStyle(alignment: Alignment.centerLeft),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }
}
