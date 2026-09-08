import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

/// Hand-written localisation for Rabochiy VPN. The app intentionally does not
/// use `flutter gen-l10n` so that all translation is contained in plain Dart
/// and can be edited without running code generation.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  // Branding
  String get appTitle;

  // Status
  String get connect;
  String get disconnect;
  String get connected;
  String get disconnected;
  String get connecting;
  String get securelyConnected;
  String get connectingUpper;
  String get cancelConnecting;
  String get disconnectingUpper;
  String get notConnected;

  // Home CTA
  String get connectNow;
  String get disconnectUpper;
  String get homeGetProPrefix;
  String get homeGetProAccent;
  String get homeGetProSuffix;

  // Transfer labels
  String get download;
  String get upload;

  // Server picker
  String get selectServer;
  String get clickToSelect;
  String get autoSelectBest;
  String get autoSelect;
  String get optimized;
  String get manualSelection;
  String get optimalServer;
  String get selectLocation;
  String get searchServers;
  String get serversNotFound;
  String get refresh;
  String get serverNotSelected;
  String get failedToLoadServers;
  String serversCount(num count);

  // Settings
  String get settings;
  String get supportTelegram;
  String get privacyPolicy;
  String get version;
  String get settingsAbout;

  // Privacy policy body
  String get privacyPolicyContent;
  String get privacyPolicyLastUpdated;

  // Bottom navigation tabs
  String get tabHome;
  String get tabAccount;
  String get tabSupport;
  String get tabSettings;

  // Support screen
  String get supportTitle;
  String get supportSubtitle;
  String get supportChannelTelegramChat;
  String get supportChannelTelegramChatDesc;
  String get supportChannelTelegramNews;
  String get supportChannelTelegramNewsDesc;
  String get supportChannelEmail;
  String get supportChannelEmailDesc;
  String get supportChannelRate;
  String get supportChannelRateDesc;
  String get supportOpen;

  // Traffic stats screen
  String get statsTitle;
  String get statsSubtitle;
  String get statsPeriodHour;
  String get statsPeriodDay;
  String get statsPeriodWeek;
  String get statsPeriodMonth;
  String get statsPeriodHalfYear;
  String get statsPeriodYear;
  String get statsPeriodAll;
  String get statsTotalTraffic;
  String get statsReceived;
  String get statsSent;
  String get statsSessions;
  String get statsOnlineTime;
  String get statsEmpty;
  String get statsResetHint;
  String get statsResetConfirm;
  String get statsResetButton;
  String get statsCancel;

  // Split tunneling
  String get splitTunnelTitle;
  String get splitTunnelSubtitle;
  String get splitTunnelEnable;
  String get splitTunnelEnableDesc;
  String get splitTunnelModeInclude;
  String get splitTunnelModeIncludeDesc;
  String get splitTunnelModeExclude;
  String get splitTunnelModeExcludeDesc;
  String get splitTunnelSearchApps;
  String get splitTunnelSelected;
  String get splitTunnelSelectAll;
  String get splitTunnelClearAll;
  String get splitTunnelLoading;
  String get splitTunnelReconnectHint;
  String get splitTunnelSystemApps;
  String get splitTunnelShowSystem;
  String get splitTunnelDisclosureTitle;
  String get splitTunnelDisclosureBody;
  String get splitTunnelDisclosureButton;

  // Server list filter chips
  String get filterAll;

  // Runtime error banners
  String get errorLoadServers;
  String get errorNoServers;
  String get errorNoServerSelected;
  String get errorVpnPermission;
  String get errorEngineNotReady;
  String get errorPlatformUnsupported;
  String errorGeneric(String details);

  // Login / Restore screen
  String get loginTitle;
  String get loginSubtitle;
  String get loginPlaceholder;
  String get loginRestoreButton;
  String get loginCreateNew;
  String get loginErrorEmpty;
  String get loginErrorWords;
  String get loginErrorInvalid;
  String get loginErrorNetwork;
  String get loginErrorServer;

  // Account / Mnemonic screen
  String get accountTitle;
  String get accountUserId;
  String get accountNotRegistered;
  String get accountRecoveryPhrase;
  String get accountShow;
  String get accountHide;
  String get accountNoMnemonic;
  String get accountTapToReveal;
  String get accountSaveMnemonicHint;
  String get accountLiveStats;
  String get accountDownloadSpeed;
  String get accountUploadSpeed;
  String get accountDuration;
  String get accountStatus;
  String get accountCopied;

  // Premium / Tariffs / Account-management actions surfaced on the
  // Account tab.
  String get accountPlanTitle;
  String get accountPlanFree;
  String get accountPlanPremium;
  String get accountPlanExpires;
  String get accountPlanUnlimited;
  String get accountBuyPremium;
  String get accountActivateCode;
  String get accountActivateCodeHint;
  String get accountActivateConfirm;
  String get accountLogout;
  String get accountLogoutConfirmTitle;
  String get accountLogoutConfirmBody;
  String get accountLogoutConfirmAction;
  String get accountDeleteAccount;
  String get accountDeleteConfirmTitle;
  String get accountDeleteConfirmBody;
  String get accountDeleteConfirmAction;
  String get accountDeleteKeep;
  String get accountDeleteSuccess;
  String get accountDeleteError;
  String get accountQrTitle;
  String get accountQrSubtitle;
  String get accountRevealMnemonic;
  String get accountMnemonicWarningTitle;
  String get accountMnemonicWarningBody;
  String get accountMnemonicWarningContinue;

  // Welcome screen (first launch)
  String get welcomeSubtitle;
  String get welcomeCreateNew;
  String get welcomeRestoreMnemonic;
  String get welcomeFooter;
  String get accountTariffsLoading;
  String get accountTariffsEmpty;
  String get accountTariffsError;
  String get premiumHeroTitle;
  String get premiumHeroAccent;
  String get premiumHeroSubtitle;
  String get premiumPickPlan;
  String get premiumBuyForLabel;
  String get premiumPriceTbd;
  String get premiumFeatureUnblock;
  String get premiumFeatureSpeed;
  String get premiumFeatureAnonymous;
  String get premiumFeatureHd;
  String get premiumFeatureNoLogs;
  String get premiumFeatureNoAds;
  String get premiumBadgeBest;
  String get accountPaymentOpenError;
  String get premiumPaymentTitle;

  String get payLoadFailed;
  String get premiumActivated;
  String get accountActivateSuccess;
  String get accountActivateInvalid;
  String get accountActivateUsed;
  String get accountActivateNetwork;
  String get accountCancel;
  String get accountClose;
  String get accountChoosePlan;

  // Splash / Onboarding
  String get splashSaveRecoveryPhrase;
  String get splashWarningMnemonic;
  String get splashCopy;
  String get splashCopied;
  String get splashSavedConfirm;
  String get splashContinue;
  String get splashRetry;
  String get splashConnectError;
  String get splashServerError;

  // Misc
  String get unknown;
  String get comingSoon;
  String get appearance;
  String get advanced;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale".',
  );
}
