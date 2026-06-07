/// Shared interface for storage exceptions that carry an underlying [cause].
///
/// Implemented by [CorruptStorageException] and [CorruptSettingsException] so
/// [buildDebugReport] (in [home_screen.dart]) can surface the inner cause
/// without a separate branch per exception type.
abstract interface class HasCause {
  Object get cause;
}
