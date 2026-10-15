import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_theme.dart';
import 'widgets/app_viewport.dart';
import 'firebase_options.dart';
import 'services/api_host_service.dart';
import 'services/remote_config_service.dart';
import 'l10n/app_localizations.dart';
import 'motion/device_tier.dart';
import 'providers/app_provider.dart';
import 'services/api_service.dart';
import 'screens/nav_shell.dart';
import 'screens/splash_screen.dart';
import 'screens/account_screen.dart';
import 'screens/login_screen.dart';
import 'screens/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Probe the device tier early so the first frame already has accurate
  // effect defaults for blur / halo / particles.
  await DeviceTierProbe.ensureInitialised();

  // Firebase initialisation is wrapped in try/catch so the app still boots
  // when placeholder keys are in place. Once you run `flutterfire configure`
  // (see FIREBASE_SETUP.md) analytics and crashlytics activate automatically.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e, st) {
    debugPrint('Firebase is not configured yet: $e');
    debugPrint('$st');
  }

  // Last Remote Config domain from disk (encoded) before any request:
  // Firebase may answer late or not at all.
  await ApiHostService.instance.restore();

  // Dynamic backend domain (Remote Config). Fired without awaiting so it
  // never blocks the first frame: until it completes (or if Firebase is
  // unreachable) the app runs on the restored or encoded default domain.
  unawaited(RemoteConfigService.instance.initialize());

  // Ограничиваем ориентацию экрана только портретным режимом
  // Крупные VPN-приложения обычно работают только вертикально, чтобы избежать поломок верстки
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Pick the entry route up-front so the user never sees the splash
  // screen flash before being routed away from it.
  //   - already onboarded (user_id present)        -> /home
  //   - fresh install (no user_id)                 -> /welcome
  //   - half-finished signup (user_id == 'pending') -> /welcome (let them
  //     choose between create / restore again, the splash flow will
  //     pick the trash-pending state up correctly when they tap
  //     "I'm a new user").
  String initialRoute = '/welcome';
  try {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(ApiService.userIdPrefsKey);
    final mnemonic = prefs.getString(ApiService.mnemonicPrefsKey);
    final mnemonicConfirmed =
        prefs.getBool(ApiService.mnemonicConfirmedPrefsKey) ?? true;
    final hasPendingMnemonic =
        !mnemonicConfirmed && mnemonic != null && mnemonic.isNotEmpty;
    if (userId != null && userId.isNotEmpty && userId != 'pending') {
      initialRoute = hasPendingMnemonic ? '/' : '/home';
    }
  } catch (_) {
    /* prefs unavailable — default to /welcome */
  }

  runApp(RabochiyVpnApp(initialRoute: initialRoute));
}

class RabochiyVpnApp extends StatelessWidget {
  const RabochiyVpnApp({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    FirebaseAnalyticsObserver? analyticsObserver;
    try {
      analyticsObserver = FirebaseAnalyticsObserver(
        analytics: FirebaseAnalytics.instance,
      );
    } catch (_) {
      // Firebase not initialised - navigator observer is optional.
      analyticsObserver = null;
    }

    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppProvider())],
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        builder: (context, child) => AppViewport(child: child),
        navigatorObservers: [?analyticsObserver],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        // Kill the default Android 12+ stretch/glow overscroll. The
        // stretch effect was squashing the liquid-glass tiles at the
        // extremes of the scroll range, which made their top/bottom
        // highlight lines bunch up and look darker — the "почему при
        // сильном листании тайлы становятся темнее?" bug.
        scrollBehavior: const _NoOverscrollBehavior(),
        initialRoute: initialRoute,
        onGenerateInitialRoutes: (String initialRouteName) {
          WidgetBuilder builder;
          switch (initialRouteName) {
            case '/home':
              builder = (context) => const NavShell();
              break;
            case '/welcome':
              builder = (context) => const WelcomeScreen();
              break;
            default:
              builder = (context) => const SplashScreen();
              break;
          }
          return [
            MaterialPageRoute(
              builder: builder,
              settings: RouteSettings(name: initialRouteName),
            ),
          ];
        },
        routes: {
          '/': (context) => const SplashScreen(),
          '/welcome': (context) => const WelcomeScreen(),
          '/home': (context) => const NavShell(),
          '/account': (context) => const AccountScreen(),
          '/login': (context) => const LoginScreen(),
        },
      ),
    );
  }
}

/// Scroll behavior that keeps the default press-highlight (InkWell) and
/// scrollbar behaviour but removes the stretch / glowing overscroll
/// indicator painted over content. Without this, overscrolling on any
/// list (Settings, Support, Traffic, Split Tunnel) would visually
/// darken the first / last tiles for a split second.
class _NoOverscrollBehavior extends MaterialScrollBehavior {
  const _NoOverscrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
