# R8/ProGuard keep rules for the release build.
#
# Flutter enables R8 code-shrinking for release builds by default
# (FlutterPlugin sets isMinifyEnabled = true when shouldShrinkResources is on).
# mobile_scanner's ML Kit barcode-scanning registers its components reflectively
# through com.google.firebase.components.ComponentDiscovery, so R8 strips the
# no-arg constructors of those ComponentRegistrar classes. ML Kit then fails to
# initialise and throws a NullPointerException the moment the scanner starts —
# only in release (debug doesn't shrink). Keep ML Kit and its registrars intact.
-keep class com.google.mlkit.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-dontwarn com.google.mlkit.**
