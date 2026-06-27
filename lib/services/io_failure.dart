import 'dart:io' show FileSystemException;

/// User-facing message for the one share/save/export failure the user can
/// actually resolve — running out of storage. Shared by every caller so the
/// wording stays consistent; pair it with [OutOfSpaceException].
const String kOutOfSpaceMessage =
    'Er is te weinig opslagruimte. Maak ruimte vrij en probeer het opnieuw.';

/// Thrown by the file-writing services ([saveFile], [shareFile]) when a write
/// fails for lack of disk space. Callers catch this to show [kOutOfSpaceMessage]
/// instead of a generic error; every *other* failure stays a raw error they
/// treat as an unknown/bug failure. This keeps the `dart:io`/errno knowledge in
/// the service layer, out of the UI.
class OutOfSpaceException implements Exception {
  const OutOfSpaceException();

  @override
  String toString() => 'OutOfSpaceException: no space left on device';
}

/// POSIX `ENOSPC` ("no space left on device") — the same value on Android, iOS
/// and Linux, Bonken's only native targets — so a bare errno check reliably
/// isolates the user-fixable out-of-space case from other write failures.
const int _enospc = 28;

/// Runs [write] and translates a disk-full [FileSystemException] into a typed
/// [OutOfSpaceException]; every other error propagates unchanged. Lets a service
/// wrap its file I/O so callers can tell "out of space" apart from a real bug
/// without inspecting `dart:io` errnos themselves.
Future<T> mapWriteFailures<T>(Future<T> Function() write) async {
  try {
    return await write();
  } on FileSystemException catch (e) {
    if (e.osError?.errorCode == _enospc) throw const OutOfSpaceException();
    rethrow;
  }
}
