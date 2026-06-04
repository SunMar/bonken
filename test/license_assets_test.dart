// Drift guard for bundled font assets and license registrations.
//
// Catches three classes of silent failures:
//  1. A botched google_fonts version bump that drops a .ttf from the asset
//     manifest (google_fonts resolves fonts by filename match; a missing entry
//     causes a silent system-font fallback or Android emoji substitution).
//  2. The Arimo LicenseRegistry entry going missing (compliance regression).
//  3. The root AGPL LICENSE asset path drifting out of sync with pubspec.

import 'package:bonken/main.dart' show registerBundledLicenses;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Font asset manifest drift guard
  // ---------------------------------------------------------------------------

  // These four .ttf files must appear in the asset manifest for google_fonts to
  // serve them offline.  The check is filename-only (version-agnostic) so it
  // stays green across google_fonts bumps without editing this file.
  const expectedFonts = [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Arimo-Regular.ttf',
  ];

  for (final filename in expectedFonts) {
    test('asset manifest contains $filename', () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets();
      expect(
        assets.any((path) => path.endsWith('/$filename') || path == filename),
        isTrue,
        reason:
            '$filename not found in asset manifest — '
            'check the assets/google_fonts/<version>/ directory and pubspec.yaml',
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Arimo LicenseRegistry entry
  // ---------------------------------------------------------------------------

  test(
    'registerBundledLicenses adds an Arimo entry to LicenseRegistry',
    () async {
      registerBundledLicenses();

      final entries = <LicenseEntry>[];
      await for (final entry in LicenseRegistry.licenses) {
        entries.add(entry);
      }
      final arimoEntries = entries.where((e) => e.packages.contains('Arimo'));
      expect(
        arimoEntries,
        isNotEmpty,
        reason: 'No Arimo entry in LicenseRegistry',
      );
      final text = arimoEntries.first.paragraphs.map((p) => p.text).join('\n');
      expect(
        text,
        contains('SIL Open Font License'),
        reason: 'Arimo license text should contain SIL Open Font License',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Arimo license asset resolves at runtime
  // ---------------------------------------------------------------------------

  test('Arimo-LICENSE.txt asset resolves at runtime', () async {
    // Version-agnostic: find the versioned dir from the asset manifest instead
    // of hardcoding '8.1.0'.
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final licensePath = manifest
        .listAssets()
        .where(
          (p) => p.contains('google_fonts') && p.endsWith('Arimo-LICENSE.txt'),
        )
        .firstOrNull;
    expect(
      licensePath,
      isNotNull,
      reason: 'Arimo-LICENSE.txt not found in asset manifest',
    );
    final text = await rootBundle.loadString(licensePath!);
    expect(
      text,
      contains('SIL Open Font License'),
      reason: 'Expected SIL OFL header in Arimo-LICENSE.txt',
    );
  });

  // ---------------------------------------------------------------------------
  // Root AGPL LICENSE asset
  // ---------------------------------------------------------------------------

  test('root LICENSE asset resolves at runtime', () async {
    final text = await rootBundle.loadString('LICENSE');
    expect(
      text,
      contains('GNU AFFERO GENERAL PUBLIC LICENSE'),
      reason: 'expected the AGPL header',
    );
  });

  // The root `LICENSE` is also surfaced in `showLicensePage()`, but via
  // a different path: it's listed in `pubspec.yaml` under
  // `flutter.assets:` and Flutter aggregates it into the build-time
  // `NOTICES` asset under the lowercase pubspec name (`bonken`). That
  // path only runs in real app builds — `flutter test` doesn't ship
  // `NOTICES` — so it can't be asserted here. The "root LICENSE asset
  // resolves at runtime" test above is the closest drift-guard we can
  // get for that path.
}
