import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Picks a `.zip` backup via the platform file picker and returns its bytes,
/// or `null` if the user cancelled. Throws on permission denial / picker
/// errors (the caller treats a throw as a cancelled pick).
Future<Uint8List?> pickBackupBytes() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['zip'],
  );
  return file == null ? null : await file.readAsBytes();
}
