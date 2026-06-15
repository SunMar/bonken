/// All three decoded parts of a backup archive. [games] / [settings] are null
/// when the original export did not include them.
typedef BackupData = ({
  Map<String, dynamic> manifest,
  List<dynamic>? games,
  Map<String, dynamic>? settings,
});

/// A single step that upgrades a backup archive from [fromVersion] to the next
/// version. Steps are applied in sequence by [runBackupMigrations] when the
/// backup's `version` is below [currentBackupVersion].
///
/// A step may reshape any part of the archive — manifest, games, or settings —
/// so [apply] receives and returns all three. Steps must handle null [games] /
/// [settings] defensively: the caller may not have decoded those streams yet.
abstract class BackupMigration {
  int get fromVersion;
  BackupData apply(BackupData data);
}

/// Ordered sequence of backup migration steps. Append here (never reorder or
/// remove) when bumping [currentBackupVersion].
const List<BackupMigration> backupMigrations = [];

/// Current backup envelope version. Bump when the ZIP structure changes.
const int currentBackupVersion = 1;

/// Applies every registered step from [fromVersion] up to
/// [currentBackupVersion], in order, returning the upgraded backup data.
///
/// Only call this when [fromVersion] < [currentBackupVersion]; the caller is
/// responsible for the version-range check. Any exception thrown by a step
/// propagates to the caller and should be treated as a migration failure.
BackupData runBackupMigrations(BackupData data, {required int fromVersion}) {
  var current = data;
  var v = fromVersion;
  for (final migration in backupMigrations) {
    if (migration.fromVersion != v) continue;
    current = migration.apply(current);
    v++;
  }
  assert(
    v == currentBackupVersion,
    'backup migration chain stalled at v$v (expected $currentBackupVersion)',
  );
  return current;
}
