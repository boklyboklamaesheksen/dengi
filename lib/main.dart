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
import 'package:responsive_framework/responsive_framework.dart';

import 'config/app_theme.dart';
import 'firebase_options.dart';
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

  // Dynamic backend domain (Remote Config). Fired without awaiting so it
  // never blocks the first frame: until it completes (or if Firebase is
  // unreachable) the app runs on the default domain from ApiConfig.
  unawaited(RemoteConfigService.instance.initialize());

  // Ограничиваем ориентацию экрана только портретным режимом
  // Крупные VPN-приложения обычно работают только вертикально, чтобы избежать поломок верстки
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

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
        title: 'Rabochiy VPN',
        builder: (context, child) {
          // Инициализируем ResponsiveFramework для пропорционального масштабирования на всех экранах.
          // Устанавливаем базовую ширину 390 (стандартный размер дизайна, например iPhone 12/13/14).
          // Все элементы (отступы, шрифты, высоты) будут пропорционально сжиматься/растягиваться
          // в зависимости от реальной ширины телефона пользователя.
          return ResponsiveBreakpoints.builder(
            child: Builder(
              builder: (context) {
                // Ограничиваем масштабирование текста системой (как делали ранее),
                // и применяем пропорциональное масштабирование всего UI:
                final mediaQuery = MediaQuery.of(context);
                final textScale = mediaQuery.textScaler.clamp(
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.15,
                );

                return MediaQuery(
                  data: mediaQuery.copyWith(textScaler: textScale),
                    child: ResponsiveScaledBox(
                      // defaultValue guards the ResponsiveValue cast: with
                      // no matching condition the package would otherwise
                      // cast null to double and crash on first frame
                      // (seen in Crashlytics on real devices).
                      width: ResponsiveValue<double>(
                        context,
                        defaultValue: 424,
                        conditionalValues: [
                        Condition.equals(name: MOBILE, value: 424),
                        Condition.largerThan(name: MOBILE, value: 424),
                      ],
                    ).value,
                    child: child!,
                  ),
                );
              },
            ),
            breakpoints: [
              const Breakpoint(start: 0, end: 450, name: MOBILE),
              const Breakpoint(start: 451, end: 800, name: TABLET),
              const Breakpoint(start: 801, end: 1920, name: DESKTOP),
              const Breakpoint(start: 1921, end: double.infinity, name: '4K'),
            ],
          );
        },
        navigatorObservers: [?analyticsObserver],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ru')],
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
