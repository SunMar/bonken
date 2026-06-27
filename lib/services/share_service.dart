import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'io_failure.dart';

/// Shares a file via the system share sheet (Android / iOS share intent,
/// Web Share API). Writes bytes to a temp file on mobile; creates an in-memory
/// [XFile] on web.
///
/// Completes normally whether the user actually shared or dismissed the sheet —
/// both are benign and need no feedback. A genuine failure *throws*:
/// [OutOfSpaceException] when a write runs out of disk space, or any other error
/// (a platform-channel error, an unsupported web environment with no fallback)
/// for the caller to surface as a generic failure. See [shareText] for the
/// text-only sibling.
Future<void> shareFile({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  String? subject,
  String? text,
}) => mapWriteFailures(() async {
  final XFile file;
  if (kIsWeb) {
    file = XFile.fromData(bytes, mimeType: mimeType, name: filename);
  } else {
    final dir = await getTemporaryDirectory();
    final ioFile = File('${dir.path}/$filename');
    await ioFile.writeAsBytes(bytes);
    file = XFile(ioFile.path);
  }
  await SharePlus.instance.share(
    ShareParams(files: [file], subject: subject, text: text),
  );
});

/// Shares plain [text] via the system share sheet. Like [shareFile]: completes
/// normally on share or dismissal, throws on a genuine failure.
Future<void> shareText({required String text, String? subject}) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}
