/// Marker interface for enum-based game-rule variants displayed in pickers
/// and settings UI. Both [StarterVariant] and [HeartsVariant] implement this.
abstract interface class LabeledVariant {
  /// Short label shown as the variant radio tile's title.
  String get label;

  /// Full sentence shown as the radio tile's subtitle and inline in the rules
  /// text.
  String get description;
}
