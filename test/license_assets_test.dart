// Drift guard for the LICENSE assets that are bundled outside the pub
// dependency graph (DejaVu Sans + the root AGPL license).
//
// `lib/main.dart` registers each one with [LicenseRegistry] using a
// hard-coded asset path. Pubspec, asset files on disk, the
// `tool/update_fonts.sh` sweep regex and `main.dart` must all agree.
// This test catches the case where one of them drifts out of sync —
// without it, `showLicensePage()` would crash at runtime the first
// time a user opens it.

import 'package:bonken/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DejaVu Sans LICENSE asset resolves at runtime', () async {
    final text = await rootBundle.loadString('assets/dejavu/2.37/LICENSE');
    expect(
      text,
      contains('Bitstream Vera'),
      reason: 'expected the Bitstream Vera + DejaVu license header',
    );
  });

  test('root LICENSE asset resolves at runtime', () async {
    final text = await rootBundle.loadString('LICENSE');
    expect(
      text,
      contains('GNU AFFERO GENERAL PUBLIC LICENSE'),
      reason: 'expected the AGPL header',
    );
  });

  test('registerBundledLicenses adds the DejaVu Sans entry', () async {
    app.registerBundledLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((e) => e.packages).toSet();
    expect(packages, contains('DejaVu Sans'));
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
