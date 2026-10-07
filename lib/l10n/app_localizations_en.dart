import 'app_localizations.dart';

class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([super.locale = 'en']);

  @override
  String get appTitle => 'Zapret VPN';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get connected => 'Connected';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get connecting => 'Connecting…';

  @override
  String get securelyConnected => 'VPN CONNECTED';

  @override
  String get connectingUpper => 'CONNECTING…';
  @override
  String get cancelConnecting => 'Tap to cancel';

  @override
  String get disconnectingUpper => 'DISCONNECTING…';

  @override
  String get notConnected => 'VPN DISCONNECTED';

  @override
  String get connectNow => 'CONNECT';

  @override
  String get disconnectUpper => 'DISCONNECT';

  @override
  String get download => 'DOWNLOAD';

  @override
  String get upload => 'UPLOAD';

  @override
  String get selectServer => 'Select server';

  @override
  String get clickToSelect => 'Tap to select';

  @override
  String get autoSelectBest => 'Auto · best server';

  @override
  String get autoSelect => 'Auto select';

  @override
  String get optimized => 'Optimized for speed';

  @override
  String get manualSelection => 'Manual selection';

  @override
  String get optimalServer => 'Fastest known server';

  @override
  String get selectLocation => 'Select location';

  @override
  String get searchServers => 'Search servers…';

  @override
  String get serversNotFound => 'No servers found';

  @override
  String get refresh => 'Refresh';

  @override
  String get serverNotSelected => 'No server selected';

  @override
  String get failedToLoadServers => 'Failed to load servers';

  @override
  String get apiConfigurationError =>
      'This build is missing its API configuration. Install a configured release or contact support.';

  @override
  String serversCount(num count) {
    if (count == 0) return 'No servers';
    if (count == 1) return '1 server';
    return '$count servers';
  }

  @override
  String get settings => 'Settings';

  @override
  String get supportTelegram => 'Telegram support';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get version => 'Version';

  @override
  String get privacyPolicyContent => _privacyPolicyEn;

  @override
  String get privacyPolicyLastUpdated => 'Last updated September 1, 2026';

  @override
  String get settingsAbout => 'About';

  // ── Bottom navigation ────────────────────────────────────────────────
  @override
  String get tabHome => 'VPN';

  @override
  String get tabAccount => 'Account';

  @override
  String get tabSupport => 'Support';

  @override
  String get tabSettings => 'Settings';

  // ── Support screen ───────────────────────────────────────────────────
  @override
  String get homeGetProPrefix => 'Buy';

  @override
  String get homeRenewProPrefix => 'Renew';

  @override
  String get homeGetProAccent => 'PRO';

  @override
  String get homeGetProSuffix => '';

  @override
  String get supportTitle => 'Support';

  @override
  String get supportSubtitle =>
      'Having trouble connecting to VPN, paying, getting good speeds, or accessing servers? Reach out to us on Telegram. We will help you figure it out and fix the issue as quickly as possible.';

  @override
  String get supportChannelTelegramChat => 'Telegram chat';

  @override
  String get supportChannelTelegramChatDesc =>
      'Live chat with support and other users';

  @override
  String get supportChannelTelegramNews => 'News channel';

  @override
  String get supportChannelTelegramNewsDesc =>
      'Updates, discounts and server announcements';

  @override
  String get supportChannelEmail => 'Email us';

  @override
  String get supportChannelEmailDesc =>
      'For detailed requests and partnerships';

  @override
  String get supportChannelRate => 'Rate the app';

  @override
  String get supportChannelRateDesc => 'Your rating helps the app grow';

  @override
  String get supportOpen => 'Open';

  // ── Traffic stats ────────────────────────────────────────────────────
  @override
  String get statsTitle => 'Traffic statistics';

  @override
  String get statsSubtitle =>
      'How much data has travelled through the VPN tunnel across periods.';

  @override
  String get statsPeriodHour => '1 hour';

  @override
  String get statsPeriodDay => '24 hours';

  @override
  String get statsPeriodWeek => '7 days';

  @override
  String get statsPeriodMonth => '1 month';

  @override
  String get statsPeriodHalfYear => '6 months';

  @override
  String get statsPeriodYear => '1 year';

  @override
  String get statsPeriodAll => 'All time';

  @override
  String get statsTotalTraffic => 'Total traffic';

  @override
  String get statsReceived => 'Received';

  @override
  String get statsSent => 'Sent';

  @override
  String get statsSessions => 'Sessions';

  @override
  String get statsOnlineTime => 'Online time';

  @override
  String get statsEmpty => 'No data for the selected period yet';

  @override
  String get statsResetHint => 'Reset all statistics';

  @override
  String get statsResetConfirm =>
      'All traffic history will be erased. This cannot be undone.';

  @override
  String get statsResetButton => 'Delete';

  @override
  String get statsCancel => 'Cancel';

  // ── Split tunneling ──────────────────────────────────────────────────
  @override
  String get splitTunnelTitle => 'Split tunneling';

  @override
  String get splitTunnelSubtitle =>
      'Choose which apps should go through the VPN and which should bypass it.';

  @override
  String get splitTunnelEnable => 'Enable split tunneling';

  @override
  String get splitTunnelEnableDesc =>
      'When disabled, all apps route through the VPN.';

  @override
  String get splitTunnelModeInclude => 'Selected apps through VPN';

  @override
  String get splitTunnelModeIncludeDesc =>
      'Only the apps you check will use the tunnel. Everything else goes direct.';

  @override
  String get splitTunnelModeExclude => 'Selected apps bypass VPN';

  @override
  String get splitTunnelModeExcludeDesc =>
      'The apps you check skip the tunnel. Everything else goes through VPN.';

  @override
  String get splitTunnelSearchApps => 'Search apps…';

  @override
  String get splitTunnelSelected => 'Selected';

  @override
  String get splitTunnelSelectAll => 'Select all';

  @override
  String get splitTunnelClearAll => 'Clear';

  @override
  String get splitTunnelLoading => 'Loading installed apps…';

  @override
  String get splitTunnelReconnectHint =>
      'Changes apply on the next VPN connection.';

  @override
  String get splitTunnelSystemApps => 'System apps';

  @override
  String get splitTunnelShowSystem => 'Show system apps';

  @override
  String get splitTunnelDisclosureTitle => 'App Access';

  @override
  String get splitTunnelDisclosureBody =>
      'To let you choose which apps route traffic through the VPN, the app needs access to the list of installed applications. This data never leaves your device and is not shared with us or third parties.';

  @override
  String get splitTunnelDisclosureButton => 'Got it';

  // ── Splash / Onboarding ──────────────────────────────────────────────
  @override
  String get splashSaveRecoveryPhrase => 'Save Your Recovery Phrase';

  @override
  String get splashWarningMnemonic =>
      'Without this phrase you will LOSE your account forever. Write it down or save it securely.';

  @override
  String get splashCopy => 'Copy';

  @override
  String get splashCopied => 'Recovery phrase copied!';

  @override
  String get splashSavedConfirm =>
      'I have saved my recovery phrase in a secure place';

  @override
  String get splashContinue => 'Continue';

  @override
  String get splashRetry => 'Retry';

  @override
  String get splashConnectError =>
      'Cannot connect to server. Please check your internet connection and try again.';

  @override
  String get splashServerError =>
      'Server connection failed. Please check your internet and try again.';

  // ── Server list filter chips ─────────────────────────────────────────
  @override
  String get filterAll => 'All';

  // ── Runtime errors ───────────────────────────────────────────────────
  @override
  String get errorLoadServers => 'Failed to load the server list';

  @override
  String get errorNoServers => 'No servers available right now';

  @override
  String get errorNoServerSelected => 'Pick a server to connect to';

  @override
  String get errorVpnPermission =>
      'Please allow the VPN connection in system settings';

  @override
  String get errorEngineNotReady =>
      'VPN engine is not ready yet. Restart the app.';

  @override
  String get errorPlatformUnsupported =>
      'VPN is currently supported only on Android';

  @override
  String get errorServerUnreachable =>
      'Server did not respond. Try another server or check your connection.';

  @override
  String errorGeneric(String details) => 'Error: $details';

  // ── Login / Restore screen ───────────────────────────────────────────
  @override
  String get loginTitle => 'Restore Account';

  @override
  String get loginSubtitle =>
      'Enter your 12-word recovery phrase to bring your account back to this device.';

  @override
  String get loginPlaceholder => 'word1 word2 word3 … word12';

  @override
  String get loginRestoreButton => 'Restore Account';

  @override
  String get loginCreateNew => 'Or create a new account';

  @override
  String get loginErrorEmpty => 'Please enter your recovery phrase';

  @override
  String get loginErrorWords => 'Recovery phrase must be 12 words';

  @override
  String get loginErrorInvalid =>
      'The secret phrase did not match. Check your input or create a new account.';

  @override
  String get loginErrorNetwork =>
      'Cannot reach the server. Please check your internet.';

  @override
  String get loginErrorServer => 'Server error. Please try again in a moment.';

  // ── Account screen ───────────────────────────────────────────────────
  @override
  String get accountTitle => 'Account';

  @override
  String get accountUserId => 'User ID';

  @override
  String get accountNotRegistered => 'Not registered';

  @override
  String get accountRecoveryPhrase => 'Secret key for sign-in';

  @override
  String get accountShow => 'Show';

  @override
  String get accountHide => 'Hide';

  @override
  String get accountNoMnemonic => 'No mnemonic available';

  @override
  String get accountTapToReveal =>
      'Use this key to sign in to your account on a new device.\nKeep this key in a safe place. Never share it with anyone, including support staff.\nIf you lose this key and have an active paid subscription, you will no longer be able to access your account.';

  @override
  String get accountSaveMnemonicHint =>
      'If you log out of your account and do not sign in for more than a year (12 months), we will delete the account to free up space for active users.';

  @override
  String get accountLiveStats => 'Live Statistics';

  @override
  String get accountDownloadSpeed => 'Download Speed';

  @override
  String get accountUploadSpeed => 'Upload Speed';

  @override
  String get accountDuration => 'Duration';

  @override
  String get accountStatus => 'Status';

  @override
  String get accountCopied => 'Copied';

  // ── Premium / tariffs / account-management actions ────────────────
  @override
  String get accountPlanTitle => 'Current plan';

  @override
  String get accountPlanFree => 'Free';

  @override
  String get accountPlanPremium => 'PRO';

  @override
  String get accountPlanExpires => 'Expires';

  @override
  String get accountPlanUnlimited => 'Unlimited';

  @override
  String get accountBuyPremium => 'Buy PRO';

  @override
  String get accountActivateCode => 'Activate code';

  @override
  String get accountActivateCodeHint => 'Enter your premium code';

  @override
  String get accountActivateConfirm => 'Activate';

  @override
  String get accountLogout => 'Log out';

  @override
  String get accountLogoutConfirmTitle => 'Log out?';

  @override
  String get accountLogoutConfirmBody =>
      'Make sure to save your secret key phrase. Without it you will permanently lose access to your account.';

  @override
  String get accountLogoutConfirmAction => 'Log out';

  @override
  String get accountDeleteAccount => 'Delete account';

  @override
  String get accountDeleteConfirmTitle =>
      'Are you sure you want to delete your account?';

  @override
  String get accountDeleteConfirmBody =>
      'You will lose your data, premium subscription and access to this account permanently. This action cannot be undone.';

  @override
  String get accountDeleteConfirmAction => 'Delete account';

  @override
  String get accountDeleteKeep => 'Keep account';

  @override
  String get accountDeleteSuccess => 'Account deleted';

  @override
  String get accountDeleteError =>
      'Failed to delete the account. Check your connection and try again.';

  @override
  String get accountQrTitle => 'Account QR';

  @override
  String get accountQrSubtitle =>
      'Used to identify your account and resolve technical issues. If you experience payment or account access problems, take a screenshot and send it to support.';

  @override
  String get accountRevealMnemonic => 'Show';

  @override
  String get accountMnemonicWarningTitle => 'Show secret key?';

  @override
  String get accountMnemonicWarningBody =>
      'Anyone with this phrase can take over your account. Make sure no one is looking at your screen and never share it with anyone.';

  @override
  String get accountMnemonicWarningContinue => 'I understand, show it';

  @override
  String get welcomeSubtitle =>
      'Create a new account or restore an existing one';

  @override
  String get welcomeCreateNew => 'I\'m a new user';

  @override
  String get welcomeRestoreMnemonic => 'Restore account';

  @override
  String get welcomeFooter => 'Enter your secret recovery phrase';

  @override
  String get accountTariffsLoading => 'Loading plans…';

  @override
  String get accountTariffsEmpty => 'No plans available right now.';

  @override
  String get accountTariffsError => 'Failed to load plans. Try again later.';

  @override
  String get premiumHeroTitle => 'Unlock the full power of';

  @override
  String get premiumHeroAccent => 'Pro';

  @override
  String get premiumHeroSubtitle =>
      'Unlimited speed, complete privacy and no ads, a working VPN always with you.';

  @override
  String get premiumPickPlan => 'Pick a plan';

  @override
  String get premiumBuyForLabel => 'Subscribe for';

  @override
  String get premiumPriceTbd => 'TBD';

  @override
  String get premiumFeatureUnblock => 'Instant access to any content';

  @override
  String get premiumFeatureSpeed => 'No speed limits';

  @override
  String get premiumFeatureAnonymous => 'Anonymous browsing';

  @override
  String get premiumFeatureHd => 'HD streaming without buffering';

  @override
  String get premiumFeatureNoLogs => 'Zero logs, full data protection';

  @override
  String get premiumFeatureNoAds => 'Ad-free experience';

  @override
  String get premiumBadgeBest => 'Best value';

  @override
  String get accountPaymentOpenError =>
      'Could not open the payment page. Try again later.';

  @override
  String get premiumPaymentTitle => 'Payment';

  @override
  String get payLoadFailed => 'Failed to load the payment page';

  @override
  String get paymentBrowserNotice =>
      'The payment page is open in your browser. Complete the payment there; your subscription will activate automatically.';
  @override
  String get paymentOpenPage => 'Open payment page';
  @override
  String get dayShort => 'd';
  @override
  String get monthShort => 'mo';
  @override
  String get yearShort => 'yr';

  @override
  String get premiumActivated => 'Subscription activated!';

  @override
  String get accountActivateSuccess => 'Code activated! Premium is now active.';

  @override
  String get accountActivateInvalid => 'Invalid or unknown code.';

  @override
  String get accountActivateUsed => 'This code has already been used.';

  @override
  String get accountActivateNetwork => 'Network error. Please try again later.';

  @override
  String get accountCancel => 'Cancel';

  @override
  String get accountClose => 'Close';

  @override
  String get accountChoosePlan => 'Choose a plan';

  // ── Misc ─────────────────────────────────────────────────────────────
  @override
  String get unknown => 'Unknown';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get appearance => 'Appearance';

  @override
  String get advanced => 'Advanced';
}

const String _privacyPolicyEn = '''
Privacy Policy — Zapret VPN
Last updated: 1 September 2026

About this document

Welcome to Zapret VPN. We respect and protect your privacy. This Privacy Policy explains how we collect, use, and safeguard your information when you use our mobile app and services. By using Zapret VPN, you agree to the terms of this Policy. If you do not agree with them, please stop using the app. Zapret VPN is an application built to provide secure and anonymous access to the Internet. We have built our service on the principles of minimal data collection. Unlike many other services, we do not log (record) your internet activity. Zapret VPN is a tool to protect your internet connection; the protocols mentioned (GW, AmneziaWG, etc.) are technical standards only and do not associate us with any services that share the same name.

What we do not do

We do not record what you do on the internet. Specifically, we are not interested in your GPS location, and we do not store: the list of websites you visit, DNS queries, the addresses of servers you connect to, your real IP address, or the timing and duration of your sessions. The servers your traffic passes through are used only for packet routing and do not keep user logs.

What is stored on your phone

The app saves a small amount of service information on your device: a cached server list (needed to work offline), your account, the last selected server, and session statistics such as speed and total connection time. All of this stays on your device only and is not transmitted anywhere. You can delete this data through your phone settings or by uninstalling the app.

Error reports

So that we can quickly find and fix bugs, the app uses Google Firebase Crashlytics. If your system allows crash reporting, an anonymous report is automatically generated when the app crashes, containing the device model, Android version, app version, and stack trace. This report does not contain any information about your network activity, IP address, subscription token, or identity. In addition, Firebase Analytics collects anonymous usage statistics, for example the fact that the app was launched or a connection succeeded. The data is aggregated and does not allow identifying a specific user. Google's privacy policy for these services is available at: https://policies.google.com/privacy

System permissions

The app requires the following permissions to operate: creating a VPN tunnel, internet access and network state monitoring, running as a foreground service (so the tunnel is not interrupted in the background), and displaying a persistent notification as required by Android. Additionally, the app requests access to the list of installed applications solely so that you can choose which apps route traffic through the VPN tunnel (Split Tunneling) and which work directly. This data does not leave your device and is not transmitted to us or third parties. The app does not request or use access to contacts, media, camera, microphone, location, SMS, or call logs.

Server configuration download

The server list and connection parameters are downloaded over an encrypted HTTPS connection. The request is sent with a unique anonymous account identifier — a random ID the server assigns automatically on first connection — that is not linked to your identity. The server does not receive device data or traffic content.

Connection metadata

To display server load and update the admin panel status, the app sends anonymous packets (connected / on server X / disconnected) to the backend whenever the VPN state changes. This data does not contain visited websites or destination IP addresses.

Account

On first launch the app automatically creates an anonymous account for you, without email, phone number, or any personal data. You are assigned a random unique identifier and a secret key. The secret key is displayed in the app and allows you to restore access to the same account on another device. We cannot link your account to your identity; it exists only as an "identifier + key" pair.

Data and account deletion

You can delete your account yourself at any time through the app settings. After deletion, the identifier and all associated subscription data are permanently removed from our servers. If an account is not used for more than 12 months after logout, it is automatically deleted. Local data on the device is removed when you uninstall the app or clear its data through Android settings.

In the current version of Zapret VPN, ad network code may be used to display ads, which allows us to maintain the free servers. Static code analysis may show tracker signatures classified as "advertising". This means that ad modules may collect anonymized data for targeted advertising, such as: Advertising ID (Ad ID); information about how you interact with ads (clicks, views). This data is collected by advertising partners (third parties) under their own privacy policies and is not linked to your activity inside the VPN tunnel. You can reset your advertising ID or opt out of ad personalization in your Android device settings.

Who the app is for

Zapret VPN is not intended for children under 13. We deliberately do not collect data from children under 13. If you become aware that a child under 13 is using the app, please let us know.

Policy updates

We reserve the right to update this document. The date in the header always reflects the current version. We will notify you of significant changes in our Telegram chat.

Contact us

Telegram: https://t.me/chatzapret
Email: support@vpnhub.ltd
''';
