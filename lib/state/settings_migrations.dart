/// One forward settings step: data at [fromVersion] → data at [fromVersion] + 1.
///
/// Steps are **frozen and self-contained**: each carries whatever historical
/// schema knowledge it needs and never reads from live app code. That way an
/// old step keeps working unchanged forever, no matter how the current models
/// evolve.
abstract class SettingsMigration {
  const SettingsMigration();

  /// The version this step upgrades *from*.
  int get fromVersion;

  /// Transforms the settings map from [fromVersion] to [fromVersion] + 1.
  Map<String, dynamic> apply(Map<String, dynamic> settings);
}

/// Latest on-disk settings schema version. Bumped whenever a new step is appended.
const int currentSettingsVersion = 1;

/// Ordered registry — append one entry per new version. Nothing else changes.
const List<SettingsMigration> _migrations = [];

/// Applies every registered step from [fromVersion] up to
/// [currentSettingsVersion], in order, returning the upgraded settings map.
Map<String, dynamic> runSettingsMigrations(
  Map<String, dynamic> settings, {
  required int fromVersion,
}) {
  var data = settings;
  var v = fromVersion;
  for (final migration in _migrations) {
    if (migration.fromVersion != v) continue;
    data = migration.apply(data);
    v++;
  }
  assert(
    v == currentSettingsVersion,
    'settings migration chain stalled at v$v (expected $currentSettingsVersion)',
  );
  return data;
}
