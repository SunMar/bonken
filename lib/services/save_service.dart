import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'save_service_io.dart'
    if (dart.library.js_interop) 'save_service_web.dart'
    as web;

/// Saves [bytes] to device storage without opening a share sheet.
///
/// Android: opens the SAF "create document" picker (defaults to Downloads).
/// iOS: auto-saves to the app's Documents directory. To make that directory
///   browsable in the Files app (On My iPhone → Bonken) the iOS project must
///   set `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` in
///   Info.plist — not yet configured (there is no committed iOS project).
/// Web: triggers a browser download.
///
/// Returns true on success, false if the user cancelled (Android SAF only).
Future<bool> saveFile({
  required Uint8List bytes,
  required String filename,
  required List<String> allowedExtensions,
}) async {
  if (kIsWeb) {
    web.webDownload(bytes, filename);
    return true;
  }

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/$filename').writeAsBytes(bytes);
    return true;
  }

  final path = await FilePicker.saveFile(
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    bytes: bytes,
  );
  return path != null;
}

Future<bool> saveZipFile({
  required Uint8List bytes,
  required String filename,
}) => saveFile(
  bytes: bytes,
  filename: filename,
  allowedExtensions: const ['zip'],
);

Future<bool> saveImageFile({
  required Uint8List bytes,
  required String filename,
}) => saveFile(
  bytes: bytes,
  filename: filename,
  allowedExtensions: const ['png'],
);
