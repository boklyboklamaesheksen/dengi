# Flutter/Firebase ship consumer rules; blanket package keeps defeat R8.
# Native-to-Java Flutter callbacks must retain their exact names.
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Optional JVM providers referenced by SSHJ, not present on Android.
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn javax.naming.**

# Flutter's optional deferred-component API is not used by this app.
-dontwarn com.google.android.play.core.tasks.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.splitcompat.**

# JNI and reflective crypto rules live beside their native engine modules.
