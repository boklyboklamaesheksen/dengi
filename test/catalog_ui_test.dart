import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rabochiy_vpn/config/app_theme.dart';
import 'package:rabochiy_vpn/config/backend_signing.dart';
import 'package:rabochiy_vpn/l10n/app_localizations.dart';
import 'package:rabochiy_vpn/providers/app_provider.dart';
import 'package:rabochiy_vpn/screens/server_list_screen.dart';
import 'package:rabochiy_vpn/screens/welcome_screen.dart';

import 'support/catalog_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI_PROOF')) return;
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (sdk == null) {
      throw StateError('Set FLUTTER_ROOT to capture readable UI proof.');
    }
    final directory = '$sdk/bin/cache/artifacts/material_fonts';
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File('$directory/${entry.value}').readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('catalogue error stays scrollable in ${locale.languageCode}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 480);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = AppProvider(
        apiService: FakeApi(
          fetch: () async => throw const BackendConfigurationException(),
        ),
        gwApiService: FakeGwApi(fetch: () async => []),
        autoInitialize: false,
      );
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const Scaffold(body: ServerListScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(provider.catalogError, 'api_not_configured');
      expect(tester.getSize(find.byType(ListView)).height, greaterThan(80));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('catalog-error')),
        80,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('catalog-error')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('welcome fits a short screen in ${locale.languageCode}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 480);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const WelcomeScreen(),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(locale);
      expect(find.text(l10n.appTitle), findsOneWidget);
      await tester.ensureVisible(find.text(l10n.welcomeRestoreMnemonic));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.welcomeRestoreMnemonic).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('catalogue shows an error and working GW servers together', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(396, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi(fetch: () async => throw Exception('AWG unavailable'));
    final provider = AppProvider(
      apiService: api,
      gwApiService: FakeGwApi(fetch: () async => [gwServer]),
      autoInitialize: false,
    );
    addTearDown(provider.dispose);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            locale: const Locale('ru'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const Scaffold(body: ServerListScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(gwServer.country), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-error')), findsOneWidget);
    expect(find.byTooltip('Обновить'), findsOneWidget);
    expect(tester.takeException(), isNull);

    if (const bool.fromEnvironment('CAPTURE_UI_PROOF')) {
      await tester.runAsync(() async {
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('.hoplite/artifacts/catalog-after.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    api.fetch = () async => throw const BackendConfigurationException();
    await tester.tap(find.byTooltip('Обновить'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        lookupAppLocalizations(const Locale('ru')).apiConfigurationError,
      ),
      findsOneWidget,
    );
    expect(find.text(gwServer.country), findsOneWidget);
    api.fetch = () async => [awgServer];
    await tester.tap(find.byTooltip('Обновить'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-error')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
