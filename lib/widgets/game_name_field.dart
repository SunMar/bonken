import 'package:flutter/material.dart';

import '../models/game_constraints.dart';
import 'form_section_card.dart';

const String kGameNameSectionTitle = 'Spelnaam';
const String kGameNameSectionSubtitle =
    'Optioneel – helpt om dit spel later te herkennen of terug te vinden.';

/// The optional "game name" form section, shared by [NewGameScreen] and
/// [EditGameScreen]. The caller owns the [controller] (its lifecycle and reading
/// the trimmed value on submit).
///
/// The field carries its own programmatic name ([kGameNameSectionTitle]) via
/// [Semantics] (mirroring [DealerDropdownField]) so non-visual field-by-field
/// navigation lands on a *named* field — a section header is page structure, not
/// a field label. No visible label is set: that would print "Spelnaam" twice
/// (`InputDecoration.labelText` is avoided for the same reason).
class GameNameField extends StatelessWidget {
  const GameNameField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: kGameNameSectionTitle,
      subtitle: kGameNameSectionSubtitle,
      child: MergeSemantics(
        child: Semantics(
          label: kGameNameSectionTitle,
          textField: true,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(counterText: ''),
            maxLength: kGameNameMaxLength,
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
      ),
    );
  }
}
