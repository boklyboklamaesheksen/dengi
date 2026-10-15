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
import 'package:rabochiy_vpn/motion/glass.dart';
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
        vlessService: FakeVless(),
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
      vlessService: FakeVless(),
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
    // The header holds only the title and the close button — no refresh
    // control (the catalogue reloads automatically every time the sheet
    // opens).
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
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
    await provider.loadServers();
    await tester.pumpAndSettle();
    expect(
      find.text(
        lookupAppLocalizations(const Locale('ru')).apiConfigurationError,
      ),
      findsOneWidget,
    );
    expect(find.text(gwServer.country), findsOneWidget);
    api.fetch = () async => [awgServer];
    await provider.loadServers();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-error')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('protocol filter chips are left-aligned in one row', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(396, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = AppProvider(
      apiService: FakeApi(fetch: () async => [awgServer]),
      gwApiService: FakeGwApi(fetch: () async => [gwServer]),
      vlessService: FakeVless(),
      autoInitialize: false,
    );
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(body: ServerListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('ru'));
    // Server tiles carry a protocol badge with the same label, so scope
    // the lookup to the chip row (chips are 13 px, badges 10 px).
    Finder chip(String label) => find.byWidgetPredicate(
      (w) => w is Text && w.data == label && w.style?.fontSize == 13,
    );
    final Rect all = tester.getRect(chip(l10n.filterAll));
    final Rect awg = tester.getRect(chip('AmneziaWG 3.1'));
    final Rect gw = tester.getRect(chip('GW'));
    final Rect title = tester.getRect(find.text(l10n.selectServer));
    // First chip hugs the left edge (16 px sheet padding + 14 px chip
    // padding) rather than sitting in the middle of the sheet.
    expect(all.left, lessThan(40));
    expect(all.left, closeTo(title.left + 10, 1));
    // Chips share one row, ordered left → right.
    expect(all.center.dy, closeTo(awg.center.dy, 0.5));
    expect(awg.center.dy, closeTo(gw.center.dy, 0.5));
    expect(all.right, lessThan(awg.left));
    expect(awg.right, lessThan(gw.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('server list scrolls clear of the navigation bar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(396, 800);
    // Edge-to-edge: the sheet is drawn under a 48 dp navigation bar.
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    final provider = AppProvider(
      apiService: FakeApi(fetch: () async => [awgServer]),
      gwApiService: FakeGwApi(fetch: () async => [gwServer]),
      vlessService: FakeVless(),
      autoInitialize: false,
    );
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(body: ServerListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ListView list = tester.widget(find.byType(ListView));
    expect(list.padding?.resolve(TextDirection.ltr).bottom, 24 + 48);
    expect(tester.takeException(), isNull);
  });

  testWidgets('welcome buttons centre their labels like the home CTA', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(396, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const WelcomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('ru'));
    for (final label in [l10n.welcomeCreateNew, l10n.welcomeRestoreMnemonic]) {
      final Finder text = find.text(label);
      final Finder tile = find.ancestor(
        of: text,
        matching: find.byType(LiquidTile),
      );
      final Rect tileRect = tester.getRect(tile);
      final Rect textRect = tester.getRect(text);
      // Same 58 px slab as the home CTA (the test font is wider than
      // Roboto and may wrap the label, so only assert the minimum).
      expect(tileRect.height, greaterThanOrEqualTo(58), reason: label);
      // Label sits in the middle of the slab on both axes — the previous
      // layout let the fill shrink-wrap and pinned the text to the top.
      expect(textRect.center.dy, closeTo(tileRect.center.dy, 1), reason: label);
      expect(textRect.center.dx, closeTo(tileRect.center.dx, 1), reason: label);
      expect(textRect.top - tileRect.top, greaterThan(8), reason: label);
      expect(tileRect.bottom - textRect.bottom, greaterThan(8), reason: label);
    }
    expect(tester.takeException(), isNull);
  });
}
