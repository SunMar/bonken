// Pure functions for reading Flutter's minimum iOS deployment target and
// keeping the Xcode project's `IPHONEOS_DEPLOYMENT_TARGET` in lock-step.
//
// Flutter has no auto-float for iOS the way it does for Android's minSdk, so
// `tool/update_flutter.dart` raises the pinned target itself when a new SDK's
// minimum rises above the project's — these helpers do the parsing/patching
// without any file I/O so they can be unit-tested with fixture strings.

/// Matches `IPHONEOS_DEPLOYMENT_TARGET = <version>;` (captures the version) in
/// an Xcode `project.pbxproj` or a Flutter `project.pbxproj.tmpl` template.
final RegExp _deploymentTargetRe = RegExp(
  r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);',
);

/// Returns the single iOS deployment target declared in [pbxproj].
///
/// Throws [StateError] when none is present, or when more than one distinct
/// value appears — every build configuration is expected to agree, and a split
/// is a layout change to look at rather than silently pick a winner from.
/// [label] names the source in the error message.
String _soleDeploymentTarget(String pbxproj, String label) {
  final values = {
    for (final m in _deploymentTargetRe.allMatches(pbxproj)) m.group(1)!,
  };
  if (values.isEmpty) {
    throw StateError('No IPHONEOS_DEPLOYMENT_TARGET found in $label.');
  }
  if (values.length > 1) {
    throw StateError(
      'Conflicting IPHONEOS_DEPLOYMENT_TARGET values in $label: '
      '${(values.toList()..sort()).join(', ')}.',
    );
  }
  return values.first;
}

/// Reads Flutter's own minimum iOS deployment target from the iOS app
/// template's `project.pbxproj.tmpl`
/// (`packages/flutter_tools/templates/app/ios.tmpl/Runner.xcodeproj/project.pbxproj.tmpl`)
/// — the value a fresh `flutter create` generates and the floor Flutter
/// migrates older projects up to.
String parseFlutterMinIosDeploymentTarget(String templatePbxproj) =>
    _soleDeploymentTarget(templatePbxproj, 'the iOS app template');

/// Reads the project's current `IPHONEOS_DEPLOYMENT_TARGET`, asserting every
/// build configuration agrees.
String readIosDeploymentTarget(String projectPbxproj) =>
    _soleDeploymentTarget(projectPbxproj, 'project.pbxproj');

/// Rewrites every `IPHONEOS_DEPLOYMENT_TARGET = …;` in [projectPbxproj] to
/// [newVersion].
String patchIosDeploymentTarget(String projectPbxproj, String newVersion) =>
    projectPbxproj.replaceAll(
      _deploymentTargetRe,
      'IPHONEOS_DEPLOYMENT_TARGET = $newVersion;',
    );
