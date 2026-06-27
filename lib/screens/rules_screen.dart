import 'package:flutter/material.dart';

import '../data/game_rules.dart';
import '../models/games/game_catalog.dart';
import '../models/mini_game.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/rules_block_view.dart';

/// Full game-rules page.
///
/// When [singleGameId] is set, only that game's section is shown (used by the
/// "rules of this minigame" button on the score input screen).  Otherwise the
/// full document is rendered.
///
/// Which variant text is shown — and whether the "Spelregelvariant"
/// alternative is offered — is controlled by the variant providers and
/// `rulesEditModeProvider`, which `RulesIconButton` overrides for the pushed
/// route when rules are opened from within a game. See [RulesBlockView].
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key, this.singleGameId});

  final String? singleGameId;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final isSingleGame = singleGameId != null;
    final singleSection = isSingleGame ? gameSectionFor(singleGameId!) : null;

    final List<Widget> children;
    if (isSingleGame) {
      children = singleSection == null
          ? [Text('Geen regels gevonden voor dit spel.', style: tt.bodyMedium)]
          : [_GameSectionView(section: singleSection, asPageTitle: true)];
    } else {
      children = _buildFullDocument(context);
    }

    return AppScaffold(
      appBar: AppBar(title: const Text('Spelregels')),
      body: Scrollbar(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Semantics(
              header: true,
              child: Text(
                isSingleGame
                    ? (singleSection?.title ?? 'Spelregels')
                    : 'Bonken',
                style: tt.headlineMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (!isSingleGame) ...[
              const SizedBox(height: 8),
              Text(kRulesTagline, style: tt.bodyMedium),
            ],
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFullDocument(BuildContext context) {
    return [
      for (final s in kSectionsBeforeGames) _SectionView(section: s),
      const _SectionView(section: kNegatieveIntroSection),
      for (final g in kGameSections.where((g) => !_isPositive(g.gameId)))
        _GameSectionView(section: g),
      const _SectionView(section: kPositieveIntroSection),
      for (final g in kGameSections.where((g) => _isPositive(g.gameId)))
        _GameSectionView(section: g),
      for (final s in kSectionsAfterGames) _SectionView(section: s),
    ];
  }

  /// Category for a rules-section game id, read from the catalog (the single
  /// source of truth) rather than a hardcoded id list, so the negative/positive
  /// split stays correct if the catalog ever changes.
  static bool _isPositive(String gameId) =>
      gameById(gameId).category == GameCategory.positive;
}

/// Shared section scaffold: an optional `Semantics(header)` title followed by a
/// [RulesBlockView] per block, in a stretched column. The title text style and
/// inner padding (and whether a title shows at all) are the only things the two
/// section types vary, so they pass them in rather than copying the layout.
class _RulesSectionBody extends StatelessWidget {
  const _RulesSectionBody({
    required this.title,
    required this.titleStyle,
    required this.titlePadding,
    required this.blocks,
  });

  /// Section heading, or null to omit it (the page-title game section).
  final String? title;
  final TextStyle? titleStyle;
  final EdgeInsets titlePadding;
  final List<Block> blocks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: titlePadding,
              child: Semantics(
                header: true,
                child: Text(title!, style: titleStyle),
              ),
            ),
          for (final b in blocks) RulesBlockView(block: b),
        ],
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.section});

  final Section section;

  @override
  Widget build(BuildContext context) {
    return _RulesSectionBody(
      title: section.title,
      titleStyle: Theme.of(context).textTheme.titleLarge,
      titlePadding: const EdgeInsets.only(top: 8, bottom: 8),
      blocks: section.blocks,
    );
  }
}

class _GameSectionView extends StatelessWidget {
  const _GameSectionView({required this.section, this.asPageTitle = false});

  final GameSection section;

  /// When true, the game title is suppressed (the in-body page heading
  /// already shows it).
  final bool asPageTitle;

  @override
  Widget build(BuildContext context) {
    return _RulesSectionBody(
      title: asPageTitle ? null : section.title,
      titleStyle: Theme.of(context).textTheme.titleMedium,
      titlePadding: const EdgeInsets.only(top: 4, bottom: 6),
      blocks: section.blocks,
    );
  }
}
