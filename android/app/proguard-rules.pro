# Flutter/Firebase ship consumer rules; blanket package keeps defeat R8.
# Native-to-Java Flutter callbacks must retain their exact names.
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# 1. Play Console "Edge-to-edge may not display for all users":
#    R8 fullMode inlines single-call EdgeToEdge.enable(...) into MainActivity
#    and obfuscates androidx.activity.EdgeToEdge / SystemBarStyle, so Play's
#    static DEX scanner cannot find the call site. Keep the entry point and
#    Jetpack class names intact.
-keep class androidx.activity.EdgeToEdge {
    public static *** enable*(...);
}
-keep,allowshrinking class androidx.activity.EdgeToEdge* { *; }
-keep,allowshrinking class androidx.activity.SystemBarStyle* { *; }
-keepnames class androidx.activity.ComponentActivity
-keep,allowshrinking class androidx.core.view.WindowCompat* { *; }
-keep,allowshrinking class androidx.core.view.WindowInsetsControllerCompat* { *; }

# 2. Play Console "Your app uses deprecated APIs or parameters for edge-to-edge":
#    Flutter's Android embedding (FlutterFragmentActivity, FlutterActivity,
#    PlatformPlugin, AccessibilityBridge) and legacy compat shims reference
#    Android 15 deprecated Window bar-color / contrast methods and
#    WindowManager.LayoutParams.layoutInDisplayCutoutMode. Strip those
#    no-op calls at R8 optimization time.
-assumenosideeffects class android.view.Window {
    public void setStatusBarColor(int);
    public void setNavigationBarColor(int);
    public void setNavigationBarDividerColor(int);
    public void setStatusBarContrastEnforced(boolean);
    public void setNavigationBarContrastEnforced(boolean);
}
-assumenosideeffects class io.flutter.embedding.android.FlutterFragmentActivity {
    private void configureStatusBarForFullscreenFlutterExperience();
}
-assumenosideeffects class io.flutter.embedding.android.FlutterActivity {
    private void configureStatusBarForFullscreenFlutterExperience();
}
-assumenosideeffects class androidx.activity.EdgeToEdgeImpl {
    public void adjustLayoutInDisplayCutoutMode(android.view.Window);
}
-assumenosideeffects class androidx.activity.EdgeToEdgeApi28 {
    public void adjustLayoutInDisplayCutoutMode(android.view.Window);
}
-assumenosideeffects class androidx.activity.EdgeToEdgeApi30 {
    public void adjustLayoutInDisplayCutoutMode(android.view.Window);
}
-assumevalues class io.flutter.view.AccessibilityBridge {
    private boolean doesLayoutInDisplayCutoutModeRequireLeftInset() return false;
}
-assumevalues class android.view.WindowManager$LayoutParams {
    public int layoutInDisplayCutoutMode return 3;
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

# VLESS engine: gomobile (libv2ray.aar) binds Java classes by name over JNI.
-keep class go.** { *; }
-keep class libv2ray.** { *; }
-keep class app.rabochiy.vpn.xray.** { *; }
