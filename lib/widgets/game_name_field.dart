import 'package:flutter/material.dart';

import 'form_section_card.dart';

/// Maximum number of characters allowed in a game name.
const int kGameNameMaxLength = 50;

const String kGameNameSectionTitle = 'Spelnaam';
const String kGameNameSectionSubtitle =
    'Optioneel – helpt om dit spel later te herkennen of terug te vinden.';

/// The optional "game name" form section, shared by [NewGameScreen] and
/// [EditGameScreen]. The caller owns the [controller] (its lifecycle and reading
/// the trimmed value on submit).
///
/// No field label is set: like the dealer section it's a single field under its
/// section header, so the header read just before it is sufficient context.
class GameNameField extends StatelessWidget {
  const GameNameField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: kGameNameSectionTitle,
      subtitle: kGameNameSectionSubtitle,
      child: TextField(
        controller: controller,
        decoration: const InputDecoration(counterText: ''),
        maxLength: kGameNameMaxLength,
        textCapitalization: TextCapitalization.sentences,
      ),
    );
  }
}
