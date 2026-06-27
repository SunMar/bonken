// Tests for tool/helpers/ios_deployment_target.dart.
// No network or file I/O — pure string logic only.

import 'package:flutter_test/flutter_test.dart';

import '../../tool/helpers/ios_deployment_target.dart';

void main() {
  // Both the Flutter iOS app template and a real project.pbxproj declare the
  // deployment target once per build configuration (Debug/Release/Profile).
  String pbxprojWith(String version) =>
      '''
		buildSettings = {
			IPHONEOS_DEPLOYMENT_TARGET = $version;
		};
		buildSettings = {
			IPHONEOS_DEPLOYMENT_TARGET = $version;
		};
		buildSettings = {
			IPHONEOS_DEPLOYMENT_TARGET = $version;
		};
''';

  group('parseFlutterMinIosDeploymentTarget', () {
    test('reads the version the template uses for every config', () {
      expect(parseFlutterMinIosDeploymentTarget(pbxprojWith('13.0')), '13.0');
    });

    test('throws when the template has no deployment target', () {
      expect(
        () => parseFlutterMinIosDeploymentTarget('buildSettings = { };'),
        throwsStateError,
      );
    });
  });

  group('readIosDeploymentTarget', () {
    test('reads the project target when all configs agree', () {
      expect(readIosDeploymentTarget(pbxprojWith('14.0')), '14.0');
    });

    test('throws when the project lists conflicting targets', () {
      const mixed =
          '\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 14.0;\n'
          '\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 13.0;\n';
      expect(() => readIosDeploymentTarget(mixed), throwsStateError);
    });
  });

  group('patchIosDeploymentTarget', () {
    test('rewrites every occurrence to the new version', () {
      final patched = patchIosDeploymentTarget(pbxprojWith('14.0'), '15.0');
      expect(readIosDeploymentTarget(patched), '15.0');
      expect(patched, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 14.0;')));
      expect(
        'IPHONEOS_DEPLOYMENT_TARGET = 15.0;'.allMatches(patched).length,
        3,
      );
    });

    test('leaves content unchanged when the version already matches', () {
      final unchanged = pbxprojWith('14.0');
      expect(patchIosDeploymentTarget(unchanged, '14.0'), unchanged);
    });
  });
}
