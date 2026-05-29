/// Marker interface for enum-based game-rule variants displayed in pickers
/// and settings UI. Both [StarterVariant] and [HeartsVariant] implement this.
abstract interface class LabeledVariant {
  /// Short label shown on the segmented-button segment.
  String get label;

  /// Full sentence shown in the settings radio tile and as a tooltip.
  String get description;
}
