# Gomobile runtime used by the vendored AmneziaWG GoBackend (libwg-go.so)
-keep class go.** { *; }
-keep class org.golang.** { *; }

# Сохраняем JNI методы
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Не обфускируем enum'ы
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Сохраняем Parcelable
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Сохраняем Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# КРИТИЧНО: Сохраняем сами классы Serializable и Parcelable от обфускации имен,
# так как они передаются через Intent (BroadcastReceiver)
-keepnames class * implements java.io.Serializable
-keepnames class * implements android.os.Parcelable

# Не предупреждать о missing classes в библиотеках
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn javax.naming.**

# Игнорируем отсутствующие классы Play Core (Flutter Deferred Components)
-dontwarn com.google.android.play.core.tasks.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.splitcompat.**

# VPN Service - критично для работы VPN
-keep class android.net.VpnService { *; }
-keep class * extends android.net.VpnService { *; }

# StrongSwan/Charon JNI classes - критично для IKEv2
-keep class org.strongswan.android.logic.Scheduler { *; }
-keep class org.strongswan.android.logic.CharonVpnService { *; }
-keep class org.strongswan.android.logic.CharonVpnService$BuilderAdapter { *; }
-keep class org.strongswan.android.logic.SimpleFetcher { *; }
-keep class org.strongswan.android.logic.NetworkManager { *; }
-keep class org.strongswan.android.logic.** { *; }

# StrongSwan security and certificate classes
-keep class org.strongswan.android.security.LocalCertificateStore { *; }
-keep class org.strongswan.android.security.LocalCertificateKeyStoreProvider { *; }
-keep class org.strongswan.android.security.** { *; }
-keep class * extends java.security.Provider { *; }
-keepclassmembers class * extends java.security.Provider {
    public <init>(java.security.Provider);
}

# GW engine (hev-socks5-tunnel) — classes are looked up via JNI
-keep class hev.htproxy.** { *; }
-dontwarn hev.htproxy.**
# sshj / bouncycastle used reflectively inside the GW engine
-dontwarn org.bouncycastle.**
-dontwarn com.hierynomus.sshj.**
