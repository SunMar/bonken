import 'package:flutter/material.dart';

import '../data/game_rules.dart';
import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/rules_block_view.dart';

/// Full game-rules page.
///
/// When [singleGameId] is set, only that game's section is shown (used by the
/// "rules of this minigame" button on the score input screen).  Otherwise the
/// full document is rendered.
///
/// Pass [starterVariantOverride] / [heartsVariantOverride] to lock the variant
/// text to a specific session's rules — used when opening rules from within a
/// game so variant blocks show only the active rule without an alternative.
/// When both are null (home screen / deep link) both the active and the
/// "Spelregel variant" alternatives are shown.
class RulesScreen extends StatelessWidget {
  const RulesScreen({
    super.key,
    this.singleGameId,
    this.starterVariantOverride,
    this.heartsVariantOverride,
  });

  final String? singleGameId;

  /// When non-null, variant blocks display only this variant (no alternative).
  final StarterVariant? starterVariantOverride;

  /// When non-null, variant blocks display only this variant (no alternative).
  final HeartsVariant? heartsVariantOverride;

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
          : [
              _GameSectionView(
                section: singleSection,
                asPageTitle: true,
                starterVariantOverride: starterVariantOverride,
                heartsVariantOverride: heartsVariantOverride,
              ),
            ];
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
      for (final s in kSectionsBeforeGames)
        _SectionView(
          section: s,
          starterVariantOverride: starterVariantOverride,
          heartsVariantOverride: heartsVariantOverride,
        ),
      _SectionView(
        section: kNegatieveIntroSection,
        starterVariantOverride: starterVariantOverride,
        heartsVariantOverride: heartsVariantOverride,
      ),
      for (final g in kGameSections.where((g) => !_isPositive(g.gameId)))
        _GameSectionView(
          section: g,
          starterVariantOverride: starterVariantOverride,
          heartsVariantOverride: heartsVariantOverride,
        ),
      _SectionView(
        section: kPositieveIntroSection,
        starterVariantOverride: starterVariantOverride,
        heartsVariantOverride: heartsVariantOverride,
      ),
      for (final g in kGameSections.where((g) => _isPositive(g.gameId)))
        _GameSectionView(
          section: g,
          starterVariantOverride: starterVariantOverride,
          heartsVariantOverride: heartsVariantOverride,
        ),
      for (final s in kSectionsAfterGames)
        _SectionView(
          section: s,
          starterVariantOverride: starterVariantOverride,
          heartsVariantOverride: heartsVariantOverride,
        ),
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
  const _SectionView({
    required this.section,
    this.starterVariantOverride,
    this.heartsVariantOverride,
  });

  final Section section;
  final StarterVariant? starterVariantOverride;
  final HeartsVariant? heartsVariantOverride;

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
            child: Semantics(
              header: true,
              child: Text(section.title, style: tt.titleLarge),
            ),
          ),
          for (final b in section.blocks)
            RulesBlockView(
              block: b,
              starterVariantOverride: starterVariantOverride,
              heartsVariantOverride: heartsVariantOverride,
            ),
        ],
      ),
    );
  }
}

class _GameSectionView extends StatelessWidget {
  const _GameSectionView({
    required this.section,
    this.asPageTitle = false,
    this.starterVariantOverride,
    this.heartsVariantOverride,
  });

  final GameSection section;

  /// When true, the game title is suppressed (the in-body page heading
  /// already shows it).
  final bool asPageTitle;
  final StarterVariant? starterVariantOverride;
  final HeartsVariant? heartsVariantOverride;

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
              child: Semantics(
                header: true,
                child: Text(section.title, style: tt.titleMedium),
              ),
            ),
          for (final b in section.blocks)
            RulesBlockView(
              block: b,
              starterVariantOverride: starterVariantOverride,
              heartsVariantOverride: heartsVariantOverride,
            ),
        ],
      ),
    );
  }
}
