# Exact JNI entry points in the bundled Go backend.
-keep class org.amnezia.awg.GoBackend { *; }
-keep class org.amnezia.awg.backend.GoBackend { *; }
-keep class org.amnezia.awg.backend.GoBackend$VpnService { *; }

# Config/crypto/util use direct calls; no package-wide keep is needed.
