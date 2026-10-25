import 'app_localizations.dart';

class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([super.locale = 'ru']);

  @override
  String get appTitle => 'Запрет VPN';

  @override
  String get paymentBrowserNotice =>
      'Страница оплаты открыта в браузере. Завершите платёж там — подписка активируется автоматически.';
  @override
  String get paymentOpenPage => 'Открыть страницу оплаты';
  @override
  String get dayShort => 'д';
  @override
  String get monthShort => 'мес';
  @override
  String get yearShort => 'г';

  @override
  String get connect => 'Подключить';

  @override
  String get disconnect => 'Отключить';

  @override
  String get connected => 'Подключено';

  @override
  String get disconnected => 'Отключено';

  @override
  String get connecting => 'Подключение…';

  @override
  String get securelyConnected => 'VPN ПОДКЛЮЧЁН';

  @override
  String get connectingUpper => 'ПОДКЛЮЧЕНИЕ…';
  @override
  String get cancelConnecting => 'Нажмите, чтобы отменить';

  @override
  String get disconnectingUpper => 'ОТКЛЮЧЕНИЕ…';

  @override
  String get notConnected => 'VPN ОТКЛЮЧЁН';

  @override
  String get connectNow => 'ПОДКЛЮЧИТЬ';

  @override
  String get disconnectUpper => 'ОТКЛЮЧИТЬ';

  @override
  String get download => 'ЗАГРУЗКА';

  @override
  String get upload => 'ОТДАЧА';

  @override
  String get selectServer => 'Выберите сервер';

  @override
  String get clickToSelect => 'Нажмите, чтобы выбрать';

  @override
  String get autoPickTitle => 'Автоподбор серверов';

  @override
  String get autoSelect => 'Автовыбор';

  @override
  String get autoPickSubtitle => 'Сам найдёт рабочий сервер';

  @override
  String get autoPickDescription =>
      'Переберёт все серверы GW, VLESS и AmneziaWG и подключит к рабочему';

  @override
  String get autoPickChecking => 'Проверка';

  @override
  String get autoPickWorking => 'Рабочий сервер';

  @override
  String get autoPickLastWorking => 'Последний рабочий';

  @override
  String get autoPickSearchingUpper => 'ПОДБОР СЕРВЕРА…';

  @override
  String get manualSelection => 'Ручной выбор';

  @override
  String get optimalServer => 'Самый быстрый сервер';

  @override
  String get selectLocation => 'Выбор локации';

  @override
  String get searchServers => 'Поиск серверов…';

  @override
  String get serversNotFound => 'Сервера не найдены';

  @override
  String get refresh => 'Обновить';

  @override
  String get serverNotSelected => 'Сервер не выбран';

  @override
  String get failedToLoadServers => 'Не удалось загрузить список серверов';

  @override
  String get apiConfigurationError =>
      'В этой сборке отсутствует настройка API. Установите настроенную версию или обратитесь в поддержку.';

  @override
  String serversCount(num count) {
    final n = count.toInt();
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (n == 0) return 'Нет серверов';
    if (mod10 == 1 && mod100 != 11) return '$n сервер';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return '$n сервера';
    }
    return '$n серверов';
  }

  @override
  String get settings => 'Настройки';

  @override
  String get supportTelegram => 'Поддержка в Telegram';

  @override
  String get privacyPolicy => 'Политика конфиденциальности';

  @override
  String get version => 'Версия';

  @override
  String get settingsAbout => 'О приложении';

  @override
  String get privacyPolicyContent => _privacyPolicyRu;

  @override
  String get privacyPolicyLastUpdated => 'Обновлено 1 сентября 2026 г.';

  // ── Bottom navigation ────────────────────────────────────────────────
  @override
  String get tabHome => 'VPN';

  @override
  String get tabAccount => 'Аккаунт';

  @override
  String get tabSupport => 'Поддержка';

  @override
  String get tabSettings => 'Настройки';

  // ── Support screen ───────────────────────────────────────────────────
  @override
  String get homeGetProPrefix => 'Купить';

  @override
  String get homeRenewProPrefix => 'Продлить';

  @override
  String get homeGetProAccent => 'PRO';

  @override
  String get homeGetProSuffix => '';

  @override
  String get supportTitle => 'Поддержка';

  @override
  String get supportSubtitle =>
      'Если у вас возникли проблемы с подключением VPN, оплатой, скоростью или доступом к серверам, обращайтесь к нам в Telegram. Мы поможем разобраться и решить вопрос как можно быстрее.';

  @override
  String get supportChannelTelegramChat => 'Чат в Telegram';

  @override
  String get supportChannelTelegramChatDesc =>
      'Живой чат с поддержкой и другими пользователями';

  @override
  String get supportChannelTelegramNews => 'Канал новостей';

  @override
  String get supportChannelTelegramNewsDesc =>
      'Обновления, скидки и анонсы серверов';

  @override
  String get supportChannelEmail => 'Написать на почту';

  @override
  String get supportChannelEmailDesc =>
      'Для детальных обращений и сотрудничества';

  @override
  String get supportChannelRate => 'Оценить приложение';

  @override
  String get supportChannelRateDesc =>
      'Ваша оценка помогает развитию приложения';

  @override
  String get supportOpen => 'Открыть';

  @override
  String get supportChatAction => 'Написать в чат';

  @override
  String get supportNewsAction => 'Подписаться';

  // ── Traffic stats ────────────────────────────────────────────────────
  @override
  String get statsTitle => 'Статистика трафика';

  @override
  String get statsSubtitle =>
      'Сколько данных прошло через VPN-туннель за разные периоды.';

  @override
  String get statsPeriodHour => '1 час';

  @override
  String get statsPeriodDay => '24 часа';

  @override
  String get statsPeriodWeek => '7 дней';

  @override
  String get statsPeriodMonth => '1 месяц';

  @override
  String get statsPeriodHalfYear => '6 месяцев';

  @override
  String get statsPeriodYear => '1 год';

  @override
  String get statsPeriodAll => 'Всё время';

  @override
  String get statsTotalTraffic => 'Всего трафика';

  @override
  String get statsReceived => 'Получено';

  @override
  String get statsSent => 'Отправлено';

  @override
  String get statsSessions => 'Сессий';

  @override
  String get statsOnlineTime => 'Время онлайн';

  @override
  String get statsEmpty => 'Пока нет данных за выбранный период';

  @override
  String get statsResetHint => 'Сбросить всю статистику';

  @override
  String get statsResetConfirm =>
      'Вся история трафика будет удалена. Действие необратимо.';

  @override
  String get statsResetButton => 'Удалить';

  @override
  String get statsCancel => 'Отмена';

  // ── Split tunneling ──────────────────────────────────────────────────
  @override
  String get splitTunnelTitle => 'Туннелирование приложений';

  @override
  String get splitTunnelSubtitle =>
      'Выберите, какие приложения должны проходить через VPN, а какие — напрямую.';

  @override
  String get splitTunnelEnable => 'Включить раздельное туннелирование';

  @override
  String get splitTunnelEnableDesc =>
      'Когда выключено — все приложения идут через VPN.';

  @override
  String get splitTunnelModeInclude => 'Только выбранные через VPN';

  @override
  String get splitTunnelModeIncludeDesc =>
      'Через туннель пойдут только отмеченные приложения. Остальные — в обход.';

  @override
  String get splitTunnelModeExclude => 'Выбранные в обход VPN';

  @override
  String get splitTunnelModeExcludeDesc =>
      'Отмеченные приложения будут идти в обход туннеля. Остальные — через VPN.';

  @override
  String get splitTunnelSearchApps => 'Поиск по приложениям…';

  @override
  String get splitTunnelSelected => 'Выбрано';

  @override
  String get splitTunnelSelectAll => 'Выбрать всё';

  @override
  String get splitTunnelClearAll => 'Снять всё';

  @override
  String get splitTunnelLoading => 'Загружаем список приложений…';

  @override
  String get splitTunnelReconnectHint =>
      'Изменения применяются при следующем подключении.';

  @override
  String get splitTunnelSystemApps => 'Системные приложения';

  @override
  String get splitTunnelShowSystem => 'Показывать системные';

  @override
  String get splitTunnelDisclosureTitle => 'Доступ к приложениям';

  @override
  String get splitTunnelDisclosureBody =>
      'Чтобы вы могли выбрать, какие приложения работают через VPN, приложению нужен доступ к списку установленных приложений. Эти данные не покидают ваше устройство и не передаются нам или третьим лицам.';

  @override
  String get splitTunnelDisclosureButton => 'Понятно';

  @override
  String get splitTunnelDisclosureLater => 'Не сейчас';

  @override
  String get splitTunnelAccessTitle => 'Нет доступа к списку приложений';

  @override
  String get splitTunnelAccessBody =>
      'Без этого разрешения система показывает только наше приложение, и выбрать нечего. Список не покидает ваше устройство.';

  @override
  String get splitTunnelAccessAllow => 'Разрешить доступ';

  @override
  String get splitTunnelAccessSettings => 'Открыть настройки';

  @override
  String get splitTunnelAccessSettingsHint =>
      'В настройках откройте «Разрешения», разрешите доступ к списку установленных приложений и вернитесь сюда.';

  // ── Splash / Onboarding ──────────────────────────────────────────────
  @override
  String get splashSaveRecoveryPhrase => 'Сохраните фразу восстановления';

  @override
  String get splashWarningMnemonic =>
      'Без этой фразы вы НАВСЕГДА потеряете доступ к аккаунту. Запишите или сохраните её в надёжном месте.';

  @override
  String get splashCopy => 'Копировать';

  @override
  String get splashCopied => 'Фраза скопирована!';

  @override
  String get splashSavedConfirm =>
      'Я сохранил фразу восстановления в надёжном месте';

  @override
  String get splashContinue => 'Продолжить';

  @override
  String get splashRetry => 'Повторить';

  @override
  String get splashConnectError =>
      'Не удалось подключиться к серверу. Проверьте подключение к интернету и попробуйте снова.';

  @override
  String get splashServerError =>
      'Ошибка соединения с сервером. Проверьте интернет и попробуйте снова.';

  // ── Server list filter chips ─────────────────────────────────────────
  @override
  String get filterAll => 'Все';

  // ── Runtime errors ───────────────────────────────────────────────────
  @override
  String get errorLoadServers => 'Не удалось загрузить список серверов';

  @override
  String get errorNoServers => 'Серверов нет — попробуйте позже';

  @override
  String get errorNoServerSelected => 'Выберите сервер для подключения';

  @override
  String get errorVpnPermission => 'Нужно разрешить VPN-подключение в системе';

  @override
  String get errorEngineNotReady =>
      'Движок VPN ещё не готов. Перезапустите приложение.';

  @override
  String get errorPlatformUnsupported =>
      'VPN сейчас работает только на Android';

  @override
  String get errorServerUnreachable =>
      'Сервер не отвечает. Попробуйте другой сервер или проверьте интернет.';

  @override
  String get errorAutoPickFailed =>
      'Не удалось найти рабочий сервер. Проверьте интернет и попробуйте ещё раз.';

  @override
  String get errorNoInternet =>
      'Нет подключения к интернету. Включите Wi-Fi или мобильные данные и попробуйте снова.';

  @override
  String errorGeneric(String details) => 'Ошибка: $details';

  // ── Login / Restore screen ───────────────────────────────────────────
  @override
  String get loginTitle => 'Войти в аккаунт';

  @override
  String get loginSubtitle =>
      'Введите фразу восстановления (12 слов), чтобы вернуть свой аккаунт на этом устройстве';

  @override
  String get loginPlaceholder => 'слово1 слово2 слово3 … слово12';

  @override
  String get loginRestoreButton => 'Восстановить аккаунт';

  @override
  String get loginCreateNew => 'или создать новый аккаунт';

  @override
  String get loginErrorEmpty => 'Введите фразу восстановления';

  @override
  String get loginErrorWords => 'Фраза должна содержать 12 слов';

  @override
  String get loginErrorInvalid =>
      'Секретная фраза не подошла. Проверьте правильность ввода или создайте новый аккаунт.';

  @override
  String get loginErrorNetwork =>
      'Не удалось связаться с сервером. Проверьте интернет.';

  @override
  String get loginErrorServer =>
      'Серверная ошибка. Попробуйте снова чуть позже.';

  // ── Account screen ───────────────────────────────────────────────────
  @override
  String get accountTitle => 'Аккаунт';

  @override
  String get accountUserId => 'ID пользователя';

  @override
  String get accountNotRegistered => 'Не зарегистрирован';

  @override
  String get accountRecoveryPhrase => 'Секретный ключ для входа';

  @override
  String get accountShow => 'Показать';

  @override
  String get accountHide => 'Скрыть';

  @override
  String get accountNoMnemonic => 'Мнемоника недоступна';

  @override
  String get accountTapToReveal =>
      'С помощью этого ключа вы сможете войти в свой аккаунт на новом устройстве.\nХраните этот ключ в надёжном месте. Никому его не передавайте, даже сотрудникам техподдержки.\nЕсли вы потеряете ключ, и при этом у вас была активная платная подписка, вы уже не сможете зайти в свой аккаунт.';

  @override
  String get accountSaveMnemonicHint =>
      'Если вы выйдете из вашей учётной записи и не будете заходить в неё дольше года (12 месяцев), то мы удалим аккаунт, чтобы освободить место для активных пользователей.';

  @override
  String get accountLiveStats => 'Статистика';

  @override
  String get accountDownloadSpeed => 'Скорость загрузки';

  @override
  String get accountUploadSpeed => 'Скорость отдачи';

  @override
  String get accountDuration => 'Длительность';

  @override
  String get accountStatus => 'Статус';

  @override
  String get accountCopied => 'Скопировано';

  // ── Premium / тарифы / управление аккаунтом ───────────────────────
  @override
  String get accountPlanTitle => 'Текущий тариф';

  @override
  String get accountPlanFree => 'Бесплатный';

  @override
  String get accountPlanPremium => 'PRO';

  @override
  String get accountPlanExpires => 'Действует до';

  @override
  String get accountPlanUnlimited => 'Без ограничений';

  @override
  String get accountBuyPremium => 'Купить PRO';

  @override
  String get accountActivateCode => 'Активировать код';

  @override
  String get accountActivateCodeHint => 'Введите премиум-код';

  @override
  String get accountActivateConfirm => 'Активировать';

  @override
  String get accountLogout => 'Выйти';

  @override
  String get accountLogoutConfirmTitle => 'Выйти из аккаунта?';

  @override
  String get accountLogoutConfirmBody =>
      'Обязательно сохраните вашу секретную ключ фразу. Без неё вы навсегда потеряете доступ к своему аккаунту.';

  @override
  String get accountLogoutConfirmAction => 'Выйти';

  @override
  String get accountDeleteAccount => 'Удалить аккаунт';

  @override
  String get accountDeleteConfirmTitle =>
      'Вы уверены, что хотите удалить аккаунт?';

  @override
  String get accountDeleteConfirmBody =>
      'Вы навсегда потеряете данные, премиум-подписку и доступ к аккаунту. Это действие нельзя отменить.';

  @override
  String get accountDeleteConfirmAction => 'Удалить аккаунт';

  @override
  String get accountDeleteKeep => 'Оставить аккаунт';

  @override
  String get accountDeleteSuccess => 'Аккаунт удалён';

  @override
  String get accountDeleteError =>
      'Не удалось удалить аккаунт. Проверьте подключение и попробуйте снова.';

  @override
  String get accountQrTitle => 'QR-код аккаунта';

  @override
  String get accountQrSubtitle =>
      'Используется для идентификации аккаунта и решения технических проблем. При сбоях оплаты, доступа к аккаунту сделайте скриншот и отправьте в поддержку.';

  @override
  String get accountRevealMnemonic => 'Показать';

  @override
  String get accountMnemonicWarningTitle => 'Показать секретный ключ?';

  @override
  String get accountMnemonicWarningBody =>
      'Любой, кто увидит эту фразу, сможет завладеть вашим аккаунтом. Убедитесь, что никто не смотрит на экран, и никогда никому её не передавайте.';

  @override
  String get accountMnemonicWarningContinue => 'Я понял, показать';

  @override
  String get welcomeSubtitle =>
      'Создайте новый аккаунт или войдите в существующий';

  @override
  String get welcomeCreateNew => 'Я новый пользователь';

  @override
  String get welcomeRestoreMnemonic => 'Восстановить аккаунт';

  @override
  String get welcomeFooter => 'Введите секретную фразу для восстановления';

  @override
  String get accountTariffsLoading => 'Загружаем тарифы…';

  @override
  String get accountTariffsEmpty => 'Сейчас нет доступных тарифов.';

  @override
  String get accountTariffsError =>
      'Не удалось загрузить тарифы. Попробуйте позже.';

  @override
  String get premiumHeroTitle => 'Откройте возможности';

  @override
  String get premiumHeroAccent => 'Pro';

  @override
  String get premiumHeroSubtitle =>
      'Неограниченная скорость, полная приватность и никакой рекламы, Запрет VPN всегда с вами.';

  @override
  String get premiumPickPlan => 'Выберите тариф';

  @override
  String get premiumBuyForLabel => 'Оформить за';

  @override
  String get premiumPriceTbd => 'уточняется';

  @override
  String get premiumFeatureUnblock => 'Быстрая разблокировка любого контента';

  @override
  String get premiumFeatureSpeed => 'Без ограничений скорости';

  @override
  String get premiumFeatureAnonymous => 'Анонимный просмотр';

  @override
  String get premiumFeatureHd => 'HD-видео без зависаний';

  @override
  String get premiumFeatureNoLogs => 'Без логов и защита данных';

  @override
  String get premiumFeatureNoAds => 'Без рекламы';

  @override
  String get premiumBadgeBest => 'Выгодно';

  @override
  String get premiumIncluded => 'Что входит в PRO';

  @override
  String get premiumTrustInstant => 'Мгновенная активация';

  @override
  String get premiumTrustSecure => 'Защищённая оплата';

  @override
  String get premiumTrustSupport => 'Помощь в Telegram';

  @override
  String get accountPaymentOpenError =>
      'Не удалось открыть страницу оплаты. Попробуйте позже.';

  @override
  String get premiumPaymentTitle => 'Оплата';

  @override
  String get payLoadFailed => 'Не удалось загрузить страницу оплаты';

  @override
  String get premiumActivated => 'Подписка активирована!';

  @override
  String get accountActivateSuccess => 'Код активирован! Премиум подключён.';

  @override
  String get accountActivateInvalid => 'Неверный или неизвестный код.';

  @override
  String get accountActivateUsed => 'Этот код уже использовался.';

  @override
  String get accountActivateNetwork => 'Ошибка сети. Попробуйте позже.';

  @override
  String get accountCancel => 'Отмена';

  @override
  String get accountClose => 'Закрыть';

  @override
  String get accountChoosePlan => 'Выберите тариф';

  // ── Misc ─────────────────────────────────────────────────────────────
  @override
  String get unknown => 'Неизвестно';

  @override
  String get comingSoon => 'Скоро будет';

  @override
  String get appearance => 'Внешний вид';

  @override
  String get advanced => 'Дополнительно';

  // ── Обновление через Google Play ─────────────────────────────────────
  @override
  String get updateReadyMessage =>
      'Обновление загружено. Перезапустите приложение, чтобы установить его.';

  @override
  String get updateReadyVpnMessage =>
      'Обновление загружено. Перезапуск для установки отключит VPN.';

  @override
  String get updateRestartAction => 'Перезапустить';
}

const String _privacyPolicyRu = '''
Политика конфиденциальности — Запрет VPN
Дата последнего обновления: 1 сентября 2026 г.

О документе

Добро пожаловать в Запрет VPN. Мы уважаем и защищаем вашу конфиденциальность. Настоящая Политика конфиденциальности объясняет, как мы собираем, используем и защищаем вашу информацию при использовании нашего мобильного приложения и услуг. Используя Запрет VPN, вы соглашаетесь с условиями данной Политики. Если вы не согласны с ними, пожалуйста, прекратите использование приложения. Запрет VPN — это приложение, созданное для обеспечения безопасного и анонимного доступа в Интернет. Мы построили наш сервис на принципах минимального сбора данных. В отличие от многих других сервисов, мы не ведем логи (не записываем) вашей интернет-активности. Запрет VPN — это инструмент для защиты вашего интернет-соединения; упоминаемые протоколы такие как (GW, AmneziaWG и др.) являются лишь техническими стандартами и не связывают нас с какими-либо одноимёнными сервисами.

Что мы не делаем

Мы не записываем, что вы делаете в интернете. Конкретно, нас не интересует ваше местоположение по GPS, не храним ни список сайтов, которые вы посещаете, ни DNS-запросы, ни адреса серверов, к которым вы обращаетесь, ни ваш настоящий IP-адрес, ни время и продолжительность ваших сессий. Серверы, через которые проходит трафик, используются только для маршрутизации пакетов и не ведут пользовательских логов.

Что хранится у вас на телефоне

Приложение сохраняет на устройстве небольшой объём служебной информации: закэшированный список серверов (нужен для работы без сети), ваш аккаунт, последний выбранный сервер и статистику сессий, скорость и суммарное время подключения. Всё это остаётся только на вашем устройстве и никуда не передаётся. Удалить эти данные можно через настройки телефона или удалив приложение.

Отчёты об ошибках

Чтобы мы могли оперативно находить и исправлять баги, приложение использует Google Firebase Crashlytics. Если ваша система разрешает отправку отчётов о сбоях, при падении приложения автоматически формируется анонимный отчёт, содержащий модель устройства, версию Android, версию приложения и стек вызовов. Никаких сведений о вашей сетевой активности, IP-адресе, токене подписки или личности в этом отчёте нет. Дополнительно Firebase Analytics собирает анонимную статистику использования, например факт запуска приложения или успешного подключения. Данные агрегированы и не позволяют идентифицировать конкретного пользователя. Политика конфиденциальности Google применительно к этим сервисам доступна по адресу: https://policies.google.com/privacy

Системные разрешения

Для работы приложению необходимы следующие разрешения: создание VPN-туннеля, доступ к интернету и отслеживание состояния сети, работа в режиме foreground-службы (чтобы туннель не прерывался в фоне), отображение постоянного уведомления согласно требованиям Android. Дополнительно приложение запрашивает доступ к списку установленных приложений, исключительно для того, чтобы вы могли выбрать, какие приложения направляют трафик через VPN-туннель (Split Tunneling), а какие работают напрямую. Эти данные не покидают ваше устройство и не передаются нам или третьим лицам. Приложение не запрашивает и не использует доступ к контактам, медиатеке, камере, микрофону, геолокации, SMS или журналу звонков.

Загрузка конфигурации серверов

Список серверов и параметры подключения загружаются по зашифрованному HTTPS-соединению. Запрос отправляется с уникальным анонимным идентификатором учётной записи — случайным ID, который сервер назначает автоматически при первом подключении, — не связанным с вашей личностью. Сервер не получает данные устройства или содержимое трафика.

Метаданные подключения

Чтобы отображать загруженность серверов и обновлять статус в админ-панели, приложение отправляет на backend анонимные пакеты (подключён / на сервере X / отключён) при каждом изменении состояния VPN. Эти данные не содержат посещаемых сайтов или IP-адресов назначения.

Учётная запись

При первом запуске приложение автоматически создаёт для вас анонимную учётную запись, без email, номера телефона или каких-либо личных данных. Вам присваивается рандомный уникальный идентификатор секретный ключ. Секретный ключ отображается в приложении и позволяет восстановить доступ к той же учётной записи на другом устройстве. Мы не можем связать вашу учётную запись с вашей личностью и она существует лишь только как пара «идентификатор + ключ».

Удаление данных и учётной записи

Вы можете самостоятельно удалить свою учётную запись в любой момент через раздел настроек приложения. После удаления идентификатор и все связанные с ним данные подписки безвозвратно удаляются с наших серверов. Если после выхода из аккаунта, учётная запись не используется более 12 месяцев, она удаляется автоматически. Локальные данные на устройстве удаляются при удалении приложения или очистке его данных через настройки Android.

В текущей версии Запрет VPN код рекламных сетей может использоваться для показа рекламы, что позволяет нам поддерживать бесплатные сервера. Статический анализ кода может показывать сигнатуры трекеров, классифицируемых как «реклама». Это означает, что рекламные модули могут собирать обезличенные данные для показа таргетированной рекламы, такие как: Рекламный идентификатор (Ad ID); Информация о том, как вы взаимодействуете с рекламой (клики, просмотры). Эти данные собираются рекламными партнерами (третьими сторонами) в соответствии с их собственными политиками конфиденциальности и не связываются с вашей активностью внутри VPN-тоннеля. Вы можете сбросить свой рекламный идентификатор или отказаться от персонализации рекламы в настройках вашего устройства Android.

Для кого предназначено приложение

Запрет VPN не предназначен для детей младше 13 лет. Мы намеренно не собираем данные лиц младше 13 лет. Если вам стало известно, что ребёнок младше 13 лет использует приложение, пожалуйста, сообщите нам.

Обновления политики

Мы оставляем за собой право обновлять этот документ. Дата в заголовке всегда отражает актуальную версию. О значимых изменениях мы будем сообщать в нашем Telegram-чате.

Связаться с нами можно через

Telegram: https://t.me/chatzapret
Email: support@vpnhub.ltd
''';
