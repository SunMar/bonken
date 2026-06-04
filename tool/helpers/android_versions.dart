// Pure functions for reading Flutter's Android toolchain version pins and
// applying them to android/ build files.

/// The three version strings Flutter pins for Android builds.
typedef AndroidVersions = ({String agp, String kotlin, String gradle});

/// Extracts Flutter's pinned AGP, Kotlin, and Gradle versions from the
/// content of `packages/flutter_tools/lib/src/android/gradle_utils.dart`.
///
/// Throws [StateError] when any expected constant is absent.
AndroidVersions parseFlutterAndroidVersions(String gradleUtilsContent) {
  String extract(String constantName) {
    final match = RegExp(
      "$constantName = '([^']+)'",
    ).firstMatch(gradleUtilsContent);
    if (match == null) {
      throw StateError("'$constantName' not found in gradle_utils.dart");
    }
    return match.group(1)!;
  }

  return (
    agp: extract('templateAndroidGradlePluginVersion'),
    kotlin: extract('templateKotlinGradlePluginVersion'),
    gradle: extract('templateDefaultGradleVersion'),
  );
}

/// Returns the currently declared version of [pluginId] in a
/// `settings.gradle.kts` content string, or `null` if not found.
String? readSettingsGradlePluginVersion(String content, String pluginId) {
  return RegExp(
    'id\\("${RegExp.escape(pluginId)}"\\) version "([^"]+)"',
  ).firstMatch(content)?.group(1);
}

/// Returns the Gradle distribution version from a
/// `gradle-wrapper.properties` content string, or `null` if not found.
String? readGradleWrapperVersion(String content) {
  return RegExp(
    r'distributionUrl=.*?/gradle-([^-/]+)-.*\.zip',
  ).firstMatch(content)?.group(1);
}

/// Updates the version of [pluginId] in a `settings.gradle.kts` content
/// string. Returns the original string when the plugin is not found.
String patchSettingsGradlePlugin(
  String content,
  String pluginId,
  String newVersion,
) {
  return content.replaceFirstMapped(
    RegExp('(id\\("${RegExp.escape(pluginId)}"\\) version ")[^"]+'),
    (m) => '${m.group(1)}$newVersion',
  );
}

/// Updates the Gradle distribution version in a `gradle-wrapper.properties`
/// content string. Returns the original string when the URL pattern is not
/// found.
String patchGradleWrapper(String content, String newVersion) {
  return content.replaceFirstMapped(
    RegExp(r'(distributionUrl=.*?/gradle-)[^-/]+(-.+\.zip)'),
    (m) => '${m.group(1)}$newVersion${m.group(2)}',
  );
}
