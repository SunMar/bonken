import 'package:flutter/material.dart';

import '../data/game_rules.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/rules_block_view.dart';

/// Full game-rules page.
///
/// When [singleGameId] is set, only that game's section is shown (used by the
/// "rules of this minigame" button on the score input screen).  Otherwise the
/// full document is rendered.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key, this.singleGameId});

  final String? singleGameId;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final isSingleGame = singleGameId != null;
    final singleSection = isSingleGame ? gameSectionFor(singleGameId!) : null;

    final String pageHeading = isSingleGame
        ? (singleSection?.title ?? 'Spelregels')
        : 'Spelregels';

    final List<Widget> children;
    if (isSingleGame) {
      children = singleSection == null
          ? [Text('Geen regels gevonden voor dit spel.', style: tt.bodyMedium)]
          : [_GameSectionView(section: singleSection, asPageTitle: true)];
    } else {
      children = _buildFullDocument(context);
    }

    return AppScaffold(
      appBar: AppBar(title: const Text('Bonken')),
      body: Scrollbar(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              pageHeading,
              style: tt.headlineMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
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
      _SectionView(section: kNegatieveIntroSection),
      for (final g in kGameSections.where((g) => !_isPositive(g.gameId)))
        _GameSectionView(section: g),
      _SectionView(section: kPositieveIntroSection),
      for (final g in kGameSections.where((g) => _isPositive(g.gameId)))
        _GameSectionView(section: g),
      for (final s in kSectionsAfterGames) _SectionView(section: s),
    ];
  }

  static bool _isPositive(String gameId) => const {
    'clubs',
    'diamonds',
    'hearts',
    'spades',
    'noTrump',
  }.contains(gameId);
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.section});

  final Section section;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(section.title, style: tt.titleLarge),
          ),
          for (final b in section.blocks) RulesBlockView(block: b),
        ],
      ),
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
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!asPageTitle)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(section.title, style: tt.titleMedium),
            ),
          for (final b in section.blocks) RulesBlockView(block: b),
        ],
      ),
    );
  }
}
