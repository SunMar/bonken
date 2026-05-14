import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mini_game.dart';

import '../models/game_session.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../state/theme_mode_provider.dart';
import '../theme/app_theme_extensions.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/game_deleted_snackbar.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/scoreboard_card.dart';
import 'score_input_screen.dart';
import 'rules_screen.dart';
import 'new_game_screen.dart';

/// Corner radius (as a fraction of the icon's side length) Android
/// applies to adaptive launcher icons via the squircle mask. We reuse
/// it for the rounded-square logo treatment in [HomeScreen] and for
/// the matching splash icon in `web/index.html` so the in-app logo,
/// home-screen icon, and splash icon all share the same silhouette.
const double _kLauncherIconCornerRatio = 0.22;

/// Home screen: logo, past-games list, and "Nieuw spel" button.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final historyAsync = ref.watch(gameHistoryProvider);

    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ----------------------------------------------------------------
          // Logo / title area
          // ----------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
            child: Row(
              children: [
                // Rounded-square "launcher icon" look (matches the rounded
                // corners Android / iOS apply to the home-screen icon and
                // the splash icon in web/index.html). See
                // [_kLauncherIconCornerRatio] for the shared 22% ratio.
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(
                      56 * _kLauncherIconCornerRatio,
                    ),
                    image: const DecorationImage(
                      image: AssetImage('assets/icon/icon_bonken.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bonken',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'Scorekaart',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _RulesButton(),
                _ThemeModeButton(),
                AboutButton(),
              ],
            ),
          ),

          // ----------------------------------------------------------------
          // History list (or placeholder)
          // ----------------------------------------------------------------
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const SizedBox.shrink(),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return Center(
                    child: Text(
                      'Nog geen gespeelde spellen',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  // +1 for the "Spellen" header at index 0.
                  itemCount: sessions.length + 1,
                  // separator-i sits between item-i and item-(i+1):
                  // index 0 = below the header (smaller gap), the rest
                  // = between cards.
                  separatorBuilder: (_, index) =>
                      SizedBox(height: index == 0 ? 8 : 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          'Spellen',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.5,
                              ),
                        ),
                      );
                    }
                    final session = sessions[index - 1];
                    return _GameSessionCard(
                      session: session,
                      onDelete: () async {
                        // Capture the messenger BEFORE any awaits, so we
                        // don't depend on a context that may change.
                        final messenger = ScaffoldMessenger.of(context);
                        final container = ProviderScope.containerOf(
                          context,
                          listen: false,
                        );
                        await ref
                            .read(gameHistoryProvider.notifier)
                            .deleteGame(session.id);
                        showGameDeletedSnackBar(
                          messenger,
                          container,
                          session,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // ----------------------------------------------------------------
          // New-game button (always pinned at bottom)
          // ----------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: PrimaryActionButton(
              icon: const Icon(Symbols.add),
              label: const Text('Nieuw spel'),
              onPressed: () {
                // NewGameScreen holds its own local working state; the
                // calculator provider is only mutated when the user
                // confirms "Start spel".
                Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => const NewGameScreen()));
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Past-game card
// =============================================================================

class _GameSessionCard extends ConsumerWidget {
  const _GameSessionCard({required this.session, required this.onDelete});

  final GameSession session;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final scores = session.finalScores;
    final winners = session.isFinished ? session.winnerIndices : <int>[];

    void onTap() {
      ref.read(calculatorProvider.notifier).loadSession(session);
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ScoreInputScreen()));
    }

    // Compact density for the trailing Verwijderen IconButton (32×32
    // slot / 18dp glyph). Any future trailing icon (e.g. share, archive)
    // inherits the same size without per-button overrides.
    final compactIconTheme = compactIconButtonTheme(
      theme,
      foregroundColor: cs.onSurfaceVariant,
    );

    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );

    return Theme(
      data: compactIconTheme,
      child: ScoreboardCard(
        // Zero outer margin so the ListView's separator owns all
        // vertical spacing between cards (avoids the default Card
        // margin compounding with the separator gap).
        margin: EdgeInsets.zero,
        roundsPlayed: session.rounds.length,
        playerNames: session.playerNames,
        scores: [for (int i = 0; i < playerCount; i++) scores[i] ?? 0],
        winners: winners,
        onTap: onTap,
        // Past-game card: date on the left, delete action on the right.
        headerLabel: Text(
          formatDate(session.updatedAt),
          style: labelStyle,
          overflow: TextOverflow.ellipsis,
        ),
        headerTrailing: IconButton(
          icon: const Icon(Symbols.delete),
          tooltip: 'Verwijderen',
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _ThemeModeButton extends ConsumerWidget {
  const _ThemeModeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final icon = switch (mode) {
      ThemeMode.light => Symbols.light_mode,
      ThemeMode.dark => Symbols.dark_mode,
      ThemeMode.system => Symbols.contrast,
    };

    return PopupMenuButton<ThemeMode>(
      icon: Icon(icon),
      tooltip: 'Thema',
      onSelected: (value) =>
          ref.read(themeModeProvider.notifier).setMode(value),
      itemBuilder: (_) => [
        _themeModeItem(ThemeMode.system, Symbols.contrast, 'Systeem', mode),
        _themeModeItem(ThemeMode.light, Symbols.light_mode, 'Licht', mode),
        _themeModeItem(ThemeMode.dark, Symbols.dark_mode, 'Donker', mode),
      ],
    );
  }

  PopupMenuItem<ThemeMode> _themeModeItem(
    ThemeMode value,
    IconData icon,
    String label,
    ThemeMode current,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Text(label),
          if (value == current) ...[
            const Spacer(),
            const Icon(Symbols.check, size: 16),
          ],
        ],
      ),
    );
  }
}

/// AppBar action: opens the stock Material [showAboutDialog] populated
/// with the app icon, version line and a link to the GitHub repository.
/// The dialog's built-in "View licenses" footer button pushes the
/// licence page registered in `lib/main.dart`.
///
/// Public so widget tests can pump it directly without going through
/// the full home-screen tree.
@visibleForTesting
class AboutButton extends StatelessWidget {
  const AboutButton({super.key});

  // Compile-time constants are exposed so tests can reference the same
  // repo URL / commit without a separate source of truth.
  static const repoUrl = 'https://github.com/SunMar/bonken';
  static const gitCommit = String.fromEnvironment('GIT_COMMIT');
  static const iconAsset = 'assets/icon/icon_bonken.png';

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Symbols.info),
      tooltip: 'Over Bonken',
      onPressed: () async {
        final versionLine = await resolveAboutVersionLine();
        if (!context.mounted) return;
        showAboutDialog(
          context: context,
          applicationName: 'Bonken',
          applicationVersion: versionLine ??
              (gitCommit.isNotEmpty ? 'Commit $gitCommit' : null),
          applicationIcon: Image.asset(iconAsset, width: 48, height: 48),
          children: [
            _AboutLink(
              icon: Symbols.open_in_new,
              label: repoUrl,
              onTap: () async {
                final uri = Uri.parse(repoUrl);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        );
      },
    );
  }
}

/// Resolves the human-readable version string shown in the About dialog.
///
/// Returns `null` when [AboutButton.gitCommit] is set: the deploy-to-Pages
/// workflow injects `GIT_COMMIT` and never builds from a tag, so the
/// `PackageInfo` version would always be the meaningless `1.0.0` default
/// — we fall back to showing the commit alone via `applicationVersion`.
///
/// Pure (no [BuildContext], no widget pumping) so it can be unit-tested
/// directly.
@visibleForTesting
Future<String?> resolveAboutVersionLine() async {
  if (AboutButton.gitCommit.isNotEmpty) return null;
  if (kDebugMode || kProfileMode) return 'Ontwikkelversie';
  try {
    final info = await PackageInfo.fromPlatform();
    return 'Versie ${info.version} (build ${info.buildNumber})';
  } catch (_) {
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
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(decoration: TextDecoration.underline),
      ),
    );
  }
}

/// AppBar action: opens the game-rules screen.
class _RulesButton extends StatelessWidget {
  const _RulesButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Symbols.menu_book),
      tooltip: 'Spelregels',
      onPressed: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const RulesScreen()));
      },
    );
  }
}
