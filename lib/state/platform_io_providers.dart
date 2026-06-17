import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/file_pick_service.dart';
import '../services/save_service.dart';
import '../services/share_service.dart';

/// Dependency-injection seams for platform side-effects (the system share sheet
/// and the file picker). Production reads these providers to obtain the real
/// implementations; tests swap them via `ProviderScope.overrides` to drive the
/// share-refused / file-pick flows without touching the platform. Never inject
/// these through `@visibleForTesting` constructor params or runtime debug
/// branches — see ARCHITECTURE.md.

typedef ShareFileFn =
    Future<bool> Function({
      required Uint8List bytes,
      required String filename,
      required String mimeType,
      String? subject,
      String? text,
    });

/// Shares a file via the system share sheet. Defaults to [shareFile].
final shareFileProvider = Provider<ShareFileFn>((ref) => shareFile);

typedef ShareTextFn =
    Future<bool> Function({required String text, String? subject});

/// Shares plain text via the system share sheet. Defaults to [shareText].
final shareTextProvider = Provider<ShareTextFn>((ref) => shareText);

typedef SaveFileFn =
    Future<bool> Function({required Uint8List bytes, required String filename});

/// Saves a ZIP file to device storage without a share sheet. Defaults to [saveZipFile].
final saveZipFileProvider = Provider<SaveFileFn>((ref) => saveZipFile);

typedef PickBackupBytesFn = Future<Uint8List?> Function();

/// Picks a backup file and returns its bytes. Defaults to [pickBackupBytes].
final pickBackupBytesProvider = Provider<PickBackupBytesFn>(
  (ref) => pickBackupBytes,
);
