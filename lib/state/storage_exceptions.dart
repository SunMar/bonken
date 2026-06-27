/// Shared interface for persistence exceptions that carry an underlying [cause].
///
/// Implemented by [CorruptPersistenceException] so [buildDebugReport] (in
/// [home_screen.dart]) can surface the inner cause without a separate branch
/// per exception type.
abstract interface class HasCause {
  Object get cause;
}

/// Our own persisted data — game history OR settings — could not be loaded.
///
/// The two stores share one taxonomy because the failing store is always known
/// at the catch site (each load path reads exactly one store), so per-store
/// subtypes would add nothing. Deliberately separate from the backup/import
/// exception family (`BackupImportException` & co.): that is a different failure
/// domain — a user-picked file, recoverable via a retry dialog — whereas these
/// mean our own storage is unusable (→ error screen + reset).
sealed class PersistenceException implements Exception {
  const PersistenceException();
}

/// The stored data was written by a newer app version than this build supports.
class UnsupportedVersionException extends PersistenceException {
  const UnsupportedVersionException(this.version);

  final int version;

  @override
  String toString() =>
      'Stored data was written by a newer version of the app (v$version). '
      'Please update the app.';
}

/// The stored data can't be read (corrupt JSON, malformed structure, …).
///
/// Surfaced to the UI instead of silently discarding the user's data — they
/// see an error screen and decide.
class CorruptPersistenceException extends PersistenceException
    implements HasCause {
  const CorruptPersistenceException(this.cause);

  @override
  final Object cause;

  @override
  String toString() => 'Stored data is corrupt and could not be read: $cause';
}
