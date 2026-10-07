import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rabochiy_vpn/l10n/app_localizations.dart';

Widget localizedApp() => MaterialApp(
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Builder(builder: (context) {
    final strings = AppLocalizations.of(context)!;
    return Text('${strings.appTitle}|${strings.connect}');
  }),
);

void main() {
  test('Russian branding includes the privacy document; English is unchanged', () {
    final ru = lookupAppLocalizations(const Locale('ru'));
    expect(ru.appTitle, 'Запрет VPN');
    expect(ru.privacyPolicyContent, contains('Запрет VPN'));
    expect(ru.privacyPolicyContent, isNot(contains('Rabochiy VPN')));
    expect(ru.privacyPolicyContent, isNot(contains('Лента VPN')));
    expect(lookupAppLocalizations(const Locale('en')).appTitle, 'Zapret VPN');
  });

  test('all supported languages have documents and resolved placeholders', () {
    expect(AppLocalizations.supportedLocales.length, 14);
    for (final locale in AppLocalizations.supportedLocales) {
      final strings = lookupAppLocalizations(locale);
      expect(strings.privacyPolicyContent, contains('support@vpnhub.ltd'));
      expect(strings.paymentOpenPage, isNotEmpty);
      expect(strings.errorGeneric('example'), contains('example'));
      for (final count in [0, 1, 2, 5, 21, 22, 101]) {
        expect(strings.serversCount(count), isNot(contains('{count}')));
      }
    }
    final pl = lookupAppLocalizations(const Locale('pl'));
    expect(pl.serversCount(1), '1 serwer');
    expect(pl.serversCount(2), '2 serwery');
    expect(pl.serversCount(5), '5 serwerów');
    final cs = lookupAppLocalizations(const Locale('cs'));
    expect(cs.serversCount(2), '2 servery');
    expect(cs.serversCount(5), '5 serverů');
  });

  testWidgets('device language selects translations and English fallback', (tester) async {
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    for (final entry in <Locale, String>{
      const Locale('ru', 'RU'): 'Запрет VPN|Подключить',
      const Locale('de', 'AT'): 'Zapret VPN|Verbinden',
      const Locale('fr', 'BE'): 'Zapret VPN|Connecter',
      const Locale('pt', 'PT'): 'Zapret VPN|Ligar',
      const Locale('ja', 'JP'): 'Zapret VPN|Connect',
    }.entries) {
      tester.platformDispatcher.localesTestValue = [entry.key];
      await tester.pumpWidget(localizedApp());
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
