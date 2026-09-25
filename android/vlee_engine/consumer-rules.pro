# sshj itself needs no keep rules: its only reflection is Class.forName of
# BouncyCastleProvider, covered below. Blanket keeps of sshj and bcprov pinned
# ~72% of the app and were the cause of Play's low R8 optimization score.
-dontwarn net.schmizz.sshj.**
-dontwarn com.hierynomus.sshj.**
# sshj тянет net.i2p.crypto.eddsa, который ссылается на JDK-классы,
# отсутствующие на Android — это чистые warnings, глушим.
-dontwarn sun.security.x509.X509Key
-dontwarn net.i2p.crypto.eddsa.**
# VleeCrypto installs the full provider as "BC". It creates every algorithm SPI
# (X25519/XDH included) from class-name strings, so exactly those classes need
# their names and constructors; the rest of bcprov is shrunk and obfuscated.
-keep class org.bouncycastle.jce.provider.** { <init>(...); }
-keep class org.bouncycastle.jcajce.provider.** { <init>(...); }
-keep class org.bouncycastle.pqc.jcajce.provider.** { <init>(...); }
-keep class org.bouncycastle.jcajce.ExternalPublicKey { <init>(...); }
-dontwarn org.bouncycastle.**
-keepclasseswithmembernames class * {
    native <methods>;
}
