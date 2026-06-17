import 'dart:typed_data';

// Stub used on non-web platforms. Never called at runtime.
void webDownload(Uint8List bytes, String filename) =>
    throw UnsupportedError('webDownload is not available on this platform');
