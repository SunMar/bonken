import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// User-facing message for when the platform's share sheet is unavailable
/// (e.g. the Web Share API is not supported). Shared by every caller of
/// [shareFile] so the wording stays consistent.
const String kShareUnsupportedMessage =
    'Delen wordt niet ondersteund op dit apparaat';

/// Shares a file via the system share sheet (Android / iOS share intent,
/// Web Share API). Writes bytes to a temp file on mobile; creates an in-memory
/// [XFile] on web.
///
/// Returns `true` if the share sheet was successfully invoked, `false` when the
/// platform refused (e.g. Web Share API unavailable). Does not swallow other
/// errors (I/O failures, etc.).
Future<bool> shareFile({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  String? subject,
  String? text,
}) async {
  try {
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
    return true;
  } on PlatformException catch (_) {
    return false;
  }
}

/// Shares plain [text] via the system share sheet. Returns `true` if the share
/// sheet was invoked, `false` when the platform refused (mirrors [shareFile]).
/// Does not swallow other errors.
Future<bool> shareText({required String text, String? subject}) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    return true;
  } on PlatformException catch (_) {
    return false;
  }
}
