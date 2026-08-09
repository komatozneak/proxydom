// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppL10nRu extends AppL10n {
  AppL10nRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Teremok Connect';

  @override
  String get loginTitle => 'Вход';

  @override
  String get loginPlaceholderHint => 'Поле для телефона будет в шаге 6';

  @override
  String get loginTestButton => 'Войти (тестовая кнопка)';

  @override
  String get loginPhoneLabel => 'Введите номер телефона';

  @override
  String get loginPhoneHint => '+7 (999) 123-45-67';

  @override
  String get loginPhoneHelper =>
      'Мы позвоним вам. Последние 4 цифры номера — ваш код. Без СМС и паролей.';

  @override
  String get loginPhoneError => 'Введите корректный номер для выбранной страны';

  @override
  String get loginErrorTimeout => 'Нет ответа от сервера';

  @override
  String get loginErrorNetwork => 'Нет связи с сервером';

  @override
  String get loginErrorGeneric => 'Не удалось выполнить запрос';

  @override
  String get loginCallButton => 'Позвонить мне';

  @override
  String get loginCallingTitle => 'Звоним...';

  @override
  String get homeTitle => 'Теремок';

  @override
  String get homeVpnHint => 'VPN UI — в шагах 9+';

  @override
  String get homeDisconnected => 'Не подключено';

  @override
  String get homeConnecting => 'Подключение...';

  @override
  String get homeConnected => 'Подключено';

  @override
  String get homeTapHint => 'Нажмите на Теремок, чтобы войти';

  @override
  String get homeConnectingHint => 'Подождите, Теремок открывает дверь…';

  @override
  String get homeConnectedHint => 'Теремок на связи';

  @override
  String get homeProtected => 'Защищено';

  @override
  String get homeError => 'Ошибка подключения';

  @override
  String get homeConnect => 'Подключиться';

  @override
  String get homeDisconnect => 'Отключить';

  @override
  String get homeRegion => 'Регион';

  @override
  String get homeSettings => 'Настройки';

  @override
  String get navHome => 'Главная';

  @override
  String get navVpn => 'VPN';

  @override
  String get navLocations => 'Локации';

  @override
  String get navModes => 'Режимы';

  @override
  String get navSubscription => 'Подписка';

  @override
  String get navPremium => 'Премиум';

  @override
  String get homeTrafficRemainder => 'Остаток трафика';

  @override
  String get homeNoVpnRow => 'Что работает без VPN?';

  @override
  String get premiumHeadline => 'YouTube без рекламы';

  @override
  String get premiumBody =>
      'Премиум открывает ноды без рекламы YouTube и снимает лимит 5 ГБ.';

  @override
  String get premiumFeatureYt => 'Локации YouTube без mid-roll рекламы';

  @override
  String get premiumFeatureSpeed => 'Приоритетные выходы для стриминга';

  @override
  String get premiumUnlimitedTraffic => 'Безлимитный трафик';

  @override
  String get premiumCta => 'Оформить Премиум';

  @override
  String get premiumOpenLocations => 'Открыть локации';

  @override
  String get subscriptionTabHint =>
      'Тарифы и промокоды. Премиум открывает YouTube-локации.';

  @override
  String get locationsPremiumLocked => 'Премиум';

  @override
  String get settingsNoVpn => 'Что работает без VPN?';

  @override
  String get settingsNoVpnHint => 'Эти адреса открываются напрямую, мимо VPN';

  @override
  String get modesTitle => 'Режим';

  @override
  String get modesSubtitle => 'Как работает VPN';

  @override
  String get modeSmartTitle => 'Умный режим';

  @override
  String get modeSmartBody =>
      'Российские сайты — напрямую, зарубежные — через VPN.';

  @override
  String get modeSmartBadge => 'АВТО';

  @override
  String get modeFullTitle => 'Обычный VPN';

  @override
  String get modeFullBody =>
      'Весь интернет идёт через VPN. Максимально просто и надёжно.';

  @override
  String get modeSitesTitle => 'По сайтам';

  @override
  String get modeSitesBody =>
      'Через VPN пойдут только выбранные сайты. Остальное — напрямую.';

  @override
  String get modesVpnOffTitle => 'VPN выключен';

  @override
  String get modesVpnOffBody => 'Подключите VPN, чтобы режимы заработали';

  @override
  String get modesConfirmFullTitle => 'Точно переключить на Обычный режим?';

  @override
  String get modesConfirmFullBody =>
      'В этом режиме весь трафик идёт через VPN. Российские сервисы — Ozon, Wildberries, банки, Госуслуги… могут перестать открываться.\n\nЧтобы они работали напрямую — используйте Умный режим.';

  @override
  String get modesConfirmFullCancel => 'Не переключать';

  @override
  String get modesConfirmFullOk => 'Переключить';

  @override
  String get modesSitesSectionSmart => 'Дополнительно напрямую';

  @override
  String get modesSitesSectionSites => 'Сайты через VPN';

  @override
  String get modesSitesCustomSection => 'Свои сайты';

  @override
  String get modesSitesCustomHint => 'например, twitch.tv';

  @override
  String get modesSitesAllowlistHint =>
      'Через VPN пойдут только выбранные сайты — остальной трафик идёт напрямую и на полной скорости.';

  @override
  String get modesSitesMetaNote =>
      'Instagram и Facebook принадлежат компании Meta, признанной в России экстремистской организацией и запрещённой на территории РФ.';

  @override
  String get modesLocationTitle => 'Локация';

  @override
  String get modesLocationHint => 'Сервер и страна';

  @override
  String get modesPendingTitle => 'Нужно переподключить VPN';

  @override
  String get modesPendingBody =>
      'Изменения маршрутизации применятся после переподключения.';

  @override
  String get modesReconnect => 'Переподключить';

  @override
  String get modesReconnectingTitle => 'Переподключаем VPN…';

  @override
  String get modesReconnectingBody => 'Применяем изменения маршрутизации';

  @override
  String get modesReconnectedTitle => 'Подключено';

  @override
  String get modesReconnectFailedTitle => 'Не удалось переподключить';

  @override
  String get navSettings => 'Настройки';

  @override
  String get homeStatServer => 'Сервер';

  @override
  String get homeStatPing => 'Пинг';

  @override
  String get homeLinkOnline => 'Дом на связи';

  @override
  String get homeLinkOffline => 'Нет подключения';

  @override
  String get homeLinkLabel => 'Связь';

  @override
  String get homeStatDownload => 'Скачивание';

  @override
  String get homeStatUpload => 'Отправка';

  @override
  String get homeStatPlaceholder => '—';

  @override
  String get homeMoreMenu => 'Ещё';

  @override
  String get homeRetry => 'Повторить';

  @override
  String get homeErrorFriendly => 'Не удалось подключиться. Попробуйте снова.';

  @override
  String get homeConfigErrorFriendly =>
      'Не удалось получить конфиг. Проверьте связь и попробуйте снова.';

  @override
  String get networkErrorFriendly => 'Нет связи с сервером. Попробуйте снова.';

  @override
  String get settingsSectionAccount => 'Аккаунт';

  @override
  String get settingsSectionConnection => 'Подключение';

  @override
  String get settingsSectionApp => 'Приложение';

  @override
  String get settingsPhone => 'Номер телефона';

  @override
  String get settingsPhoneReadonly =>
      'Номер меняется только при повторном входе';

  @override
  String get settingsSubscription => 'Доступ';

  @override
  String get settingsSubscriptionActive => 'Активна';

  @override
  String get settingsProBadge => 'PRO';

  @override
  String get settingsActiveBadge => 'Активна';

  @override
  String get settingsAccessEarlyTitle => 'Закрытое тестирование';

  @override
  String get settingsAccessEarlySubtitle => 'Доступ по приглашению.';

  @override
  String get settingsAccessBetaTitle => 'Закрытое тестирование';

  @override
  String get settingsAccessBetaSubtitle =>
      'По приглашению, без даты окончания.';

  @override
  String get settingsAccessNoneTitle => 'Нет доступа';

  @override
  String get settingsAccessNoneSubtitle => 'Нужен код приглашения.';

  @override
  String settingsAccessActiveUntil(String date) {
    return 'Действует до $date.';
  }

  @override
  String get settingsAccessCancelledSubtitle => 'Автопродление выключено.';

  @override
  String settingsSubscriptionActiveUntil(String date) {
    return 'Активна до $date';
  }

  @override
  String settingsSubscriptionTrialUntil(String date) {
    return 'Пробный период до $date';
  }

  @override
  String get settingsSubscriptionAlpha => 'Закрытое тестирование';

  @override
  String get settingsSubscriptionExpired => 'Подписка истекла';

  @override
  String get settingsSubscriptionLoadError => 'Не удалось загрузить статус';

  @override
  String get settingsServerRegion => 'Регион сервера';

  @override
  String get settingsProtocol => 'Протокол';

  @override
  String get settingsProtocolLocked => 'Сейчас доступен только VLESS + Reality';

  @override
  String get settingsKillSwitch => 'Блокировка без VPN';

  @override
  String get settingsKillSwitchHint =>
      'Android будет блокировать интернет, если защищённое соединение не установлено.';

  @override
  String get settingsKillSwitchHintSystem =>
      'Включите «Всегда VPN» и «Блокировать без VPN» в системных настройках VPN';

  @override
  String get settingsKillSwitchOn => 'Включено в настройках Android';

  @override
  String get settingsKillSwitchAlwaysOnOnly =>
      'Always-on включён — включите ещё «Блокировать без VPN»';

  @override
  String get settingsKillSwitchOff =>
      'Выключено — интернет может работать без VPN';

  @override
  String get settingsKillSwitchUnavailable =>
      'Не удалось проверить настройку Android';

  @override
  String get settingsKillSwitchChecking => 'Проверка настройки Android…';

  @override
  String get settingsKillSwitchOpenVpn => 'Открыть настройки VPN';

  @override
  String get settingsKillSwitchRisk =>
      'Если соединение не восстановится, интернет останется недоступен, пока вы не отключите блокировку в настройках Android.';

  @override
  String get settingsKillSwitchOpenFailed =>
      'Не удалось открыть настройки VPN. Откройте Настройки → Сеть и интернет → VPN.';

  @override
  String get settingsKillSwitchAndroidOwned => 'Управляется в Android';

  @override
  String get settingsKillSwitchBadgeOn => 'Вкл';

  @override
  String get settingsKillSwitchBadgePartial => 'Частично';

  @override
  String get settingsKillSwitchBadgeOff => 'Выкл';

  @override
  String get settingsKillSwitchBadgeUnknown => 'Неизвестно';

  @override
  String get settingsAutoReconnect => 'Авто-переподключение';

  @override
  String get settingsAutoReconnectHint => 'Быстрое переподключение при обрыве';

  @override
  String get settingsSplitTunnel => 'Режимы';

  @override
  String get settingsSplitTunnelHint => 'Умный / обычный / по сайтам';

  @override
  String get settingsDevices => 'Устройства';

  @override
  String get settingsDevicesHint =>
      'Зарегистрированные установки и отзыв доступа';

  @override
  String get devicesTitle => 'Устройства';

  @override
  String get devicesHint =>
      'Каждая установка приложения получает свой VPN-ключ. Можно отозвать доступ к отдельному устройству.';

  @override
  String devicesCount(int active, int max) {
    return '$active из $max';
  }

  @override
  String get devicesEmpty =>
      'Пока нет устройств — подключите VPN, чтобы зарегистрировать это.';

  @override
  String get devicesLoadError => 'Не удалось загрузить список устройств';

  @override
  String get devicesUntitled => 'Устройство';

  @override
  String get devicesThisDevice => 'это устройство';

  @override
  String get devicesRevoke => 'Отозвать';

  @override
  String get devicesRevokeTitle => 'Отозвать устройство?';

  @override
  String get devicesRevokeBody =>
      'VPN-ключ этого устройства перестанет работать. Остальные устройства не затронуты.';

  @override
  String get devicesRevokeConfirm => 'Отозвать';

  @override
  String get devicesCancel => 'Отмена';

  @override
  String get devicesRevoked => 'Устройство отозвано';

  @override
  String get devicesRevokeFailed => 'Не удалось отозвать устройство';

  @override
  String get splitTunnelSearchHint => 'Поиск по моим сайтам';

  @override
  String get splitTunnelBundledSection => 'Готовый список';

  @override
  String get splitTunnelBundledLead =>
      'Уже в приложении — включается одним касанием.';

  @override
  String get splitTunnelBundledRuTitle => 'Прямой доступ для РФ';

  @override
  String get splitTunnelBundledRuSubtitle =>
      'Российские сайты и сервисы\nДомены .ru, .su и .рф\nIP-адреса в России';

  @override
  String get splitTunnelBundledInfoTitle => 'Как это работает';

  @override
  String get splitTunnelBundledInfoBody =>
      'Список вшит в Теремок и реально задаёт маршруты.\n\nВ готовый список входит:\n• российские сайты и сервисы\n• все домены .ru, .su и .рф\n• IP-адреса в России\n\nВкл — этот трафик идёт мимо VPN.\nВыкл — весь трафик через VPN.\n\nЕсли VPN уже подключён, после смены нажмите «Переподключить».';

  @override
  String get splitTunnelBundledInfoClose => 'Понятно';

  @override
  String get splitTunnelCustomSection => 'Мои сайты';

  @override
  String splitTunnelCustomCount(int count) {
    return '$count';
  }

  @override
  String get splitTunnelAddSite => 'Добавить сайт';

  @override
  String get splitTunnelSiteNameOptional => 'Название (необязательно)';

  @override
  String get splitTunnelDomainLabel => 'Адрес сайта';

  @override
  String get splitTunnelDomainHint => 'example.com';

  @override
  String get splitTunnelSave => 'Добавить';

  @override
  String get splitTunnelCancel => 'Отмена';

  @override
  String get splitTunnelDelete => 'Удалить';

  @override
  String get splitTunnelDeleteConfirm => 'Удалить сайт из списка?';

  @override
  String get splitTunnelEmptyTitle => 'Нет своих сайтов';

  @override
  String get splitTunnelEmptyBody =>
      'Добавьте адрес — он будет открываться напрямую, без VPN.';

  @override
  String get splitTunnelInvalidDomain => 'Введите адрес вида example.com';

  @override
  String get splitTunnelDuplicateDomain => 'Этот адрес уже в списке';

  @override
  String get splitTunnelNonAsciiUnsupported => 'Только латинские адреса';

  @override
  String get splitTunnelDomainLatinHelper => 'Только латинские адреса';

  @override
  String get splitTunnelPendingTitle => 'Изменения не применены';

  @override
  String get splitTunnelPendingBody =>
      'Изменения применятся после переподключения';

  @override
  String get splitTunnelReconnect => 'Переподключить';

  @override
  String get splitTunnelReconnectInProgress => 'Переподключение…';

  @override
  String get splitTunnelApplied => 'Правила применены';

  @override
  String get splitTunnelApplyFailed =>
      'Не удалось переподключить — попробуйте снова';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsComingSoon => 'Скоро — пока заглушка';

  @override
  String get settingsComingSoonBadge => 'Скоро';

  @override
  String get settingsPrivacyPlaceholder => 'Политика конфиденциальности';

  @override
  String get settingsDarkTheme => 'Оформление';

  @override
  String get settingsAppearance => 'Оформление';

  @override
  String get settingsThemeSystem => 'Авто';

  @override
  String get settingsThemeDark => 'Тёмное';

  @override
  String get settingsThemeLight => 'Светлое';

  @override
  String get settingsDiagnostics => 'Диагностика';

  @override
  String get settingsDiagnosticsHint => 'Проверить соединение';

  @override
  String settingsVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsSendReport => 'Отправить отчёт';

  @override
  String get settingsSendReportHint =>
      'Отправляется владельцу для отладки. Номер телефона маскируется на сервере.';

  @override
  String get settingsSendReportConfirm => 'Отправить';

  @override
  String get settingsReportSent => 'Отчёт отправлен';

  @override
  String get settingsReportFailed => 'Не удалось отправить отчёт';

  @override
  String get settingsReportUnauthorized =>
      'Сессия устарела — войдите снова и повторите';

  @override
  String get settingsReportNetworkError =>
      'Нет связи с сервером — попробуйте позже';

  @override
  String get settingsVpnNotificationTitle => 'Уведомление в шторке';

  @override
  String get settingsVpnNotificationHint =>
      'Подробная карточка: регион, скорость, отключение';

  @override
  String get settingsQsTileTitle => 'Плитка в шторке';

  @override
  String get settingsQsTileHint =>
      'Быстрое подключение и отключение из панели быстрых настроек Android';

  @override
  String get settingsQsTileAdd => 'Добавить в шторку';

  @override
  String get settingsQsTileAddHint =>
      'Показать системный запрос на добавление плитки';

  @override
  String get settingsQsTileAdded => 'Плитка добавлена в шторку';

  @override
  String get settingsQsTileAlreadyAdded =>
      'Плитка уже в шторке — откройте панель и пролистайте';

  @override
  String get settingsQsTileManual =>
      'Добавьте вручную: шторка → карандаш → «Теремок VPN»';

  @override
  String get homeAbout => 'О приложении';

  @override
  String homeConfigError(String message) {
    return 'Не удалось получить конфиг: $message';
  }

  @override
  String get homeFetchConfig => 'Получить конфиг';

  @override
  String homeUptime(String time) {
    return 'Время сессии: $time';
  }

  @override
  String get homeSessionLabel => 'Сессия';

  @override
  String homeServer(String name) {
    return 'Сервер: $name';
  }

  @override
  String homeIp(String ip) {
    return 'Ваш IP: $ip';
  }

  @override
  String get homeIpLoading => 'Ваш IP: …';

  @override
  String get homeIpUnavailable => 'Ваш IP: недоступен — туннель без интернета';

  @override
  String get homeIpLockdownHint =>
      'Отключите «Всегда VPN» и «Блокировать без VPN» в системных настройках VPN, затем подключитесь снова';

  @override
  String get homeRegionAuto => 'Авто';

  @override
  String get homeVpnDisconnected => 'Отключено';

  @override
  String get homeDisconnectUndo => 'Отменить';

  @override
  String get regionTitle => 'Регион';

  @override
  String get regionSubtitle =>
      'Выберите сервер или оставьте автоматический выбор';

  @override
  String get regionAutoTitle => 'Автоматически';

  @override
  String get regionAutoSubtitle => 'Лучший доступный сервер';

  @override
  String get regionSelected => 'Выбрано';

  @override
  String get regionSectionServers => 'Серверы';

  @override
  String get regionSectionGeneral => 'Основные';

  @override
  String get regionSectionYoutube => 'YouTube — без рекламы';

  @override
  String get regionComingSoon => 'Скоро появится';

  @override
  String get regionComingSoonBadge => 'Скоро';

  @override
  String get regionSectionOffline => 'Недоступные серверы';

  @override
  String get regionOnline => 'онлайн';

  @override
  String get regionOffline => 'офлайн';

  @override
  String get regionFree => 'Свободно';

  @override
  String get regionNoneOnline => 'Нет доступных серверов — попробуйте позже';

  @override
  String regionLoadError(String error) {
    return 'Не удалось загрузить список: $error';
  }

  @override
  String get regionLoadErrorAbort =>
      'API недоступен — отключите «Всегда VPN» (и «Блокировать без VPN») в системе, затем откройте список снова';

  @override
  String get regionCachedHint =>
      'Показан сохранённый список — сеть сейчас нестабильна';

  @override
  String get regionEmpty => 'Список серверов пуст';

  @override
  String regionChanged(String name) {
    return 'Регион: $name';
  }

  @override
  String regionChangeFailed(String error) {
    return 'Не удалось сменить регион: $error';
  }

  @override
  String get logoutTooltip => 'Выйти';

  @override
  String get settingsDeviceId => 'ID устройства';

  @override
  String get settingsDeviceIdCopied => 'ID скопирован';

  @override
  String get settingsDeviceIdHint => 'Идентификатор установки для поддержки';

  @override
  String get logoutConfirmTitle => 'Выйти из аккаунта?';

  @override
  String get logoutConfirmMessage =>
      'VPN-соединение будет закрыто. В следующий раз нужно будет заново ввести код.';

  @override
  String get logoutWarning => 'Выход выполнен с предупреждениями';

  @override
  String get cancel => 'Отмена';

  @override
  String get verifyTitle => 'Код из звонка';

  @override
  String verifySentTo(String phone) {
    return 'Последние 4 цифры номера, с которого позвонили на $phone';
  }

  @override
  String get verifyResend => 'Позвонить повторно';

  @override
  String verifyResendIn(int seconds) {
    return 'Позвонить повторно через 00:$seconds';
  }

  @override
  String get verifyWrongCode => 'Неверный код, попробуйте снова';

  @override
  String get switchLanguage => 'RU';

  @override
  String get updateAvailableTitle => 'Доступно обновление';

  @override
  String updateAvailableBody(String version) {
    return 'Вышла версия $version. Рекомендуем обновиться.';
  }

  @override
  String get updateNow => 'Обновить';

  @override
  String get updateLater => 'Позже';

  @override
  String get welcomeHeadline => 'Тёплый дом в холодном интернете';

  @override
  String get welcomeBody =>
      'Войдите по телефону — дальше один тап для подключения.';

  @override
  String get welcomeContinue => 'Продолжить';

  @override
  String get welcomeSkip => 'Пропустить';

  @override
  String get promoTitle => 'Код доступа';

  @override
  String get promoHeadline => 'Введите персональный код';

  @override
  String get promoBody =>
      'Пока бета закрытая — доступ по приглашению. Можно повторить без выхода из аккаунта.';

  @override
  String get promoCodeLabel => 'Код';

  @override
  String get promoCodeHint => 'Ваш промокод';

  @override
  String get promoCodeEmpty => 'Введите код';

  @override
  String get promoSubmit => 'Продолжить';

  @override
  String get promoOutcomeInvalid =>
      'Код не найден. Проверьте и попробуйте снова.';

  @override
  String get promoOutcomeExpired => 'Срок действия кода истёк.';

  @override
  String get promoOutcomeExhausted => 'Этот код уже использован.';

  @override
  String get promoOutcomeRevoked => 'Код больше не действует.';

  @override
  String get promoOutcomeRateLimited =>
      'Слишком много попыток. Подождите минуту.';

  @override
  String get promoOutcomeUnknown =>
      'Не удалось применить код. Попробуйте ещё раз.';

  @override
  String get onboardingSkip => 'Пропустить';

  @override
  String get onboardingNext => 'Далее';

  @override
  String get onboardingDone => 'Начать';

  @override
  String get onboardingConnectTitle => 'Подключение';

  @override
  String get onboardingConnectBody =>
      'На главном экране нажмите «Подключиться». Android один раз спросит разрешение VPN — так и должно быть.';

  @override
  String get onboardingRegionTitle => 'Регион';

  @override
  String get onboardingRegionBody =>
      'Рекомендуем автоматический выбор. Позже регион можно сменить в списке.';

  @override
  String get onboardingHelpTitle => 'Помощь и приватность';

  @override
  String get onboardingHelpBody =>
      'Отчёт для отладки — в Настройках. Собираем только минимальную дневную сводку: без истории сайтов, списка приложений и рекламных ID.';

  @override
  String get betaGateError => 'Не удалось проверить доступ. Проверьте связь.';

  @override
  String get betaGateContinueAnyway => 'Продолжить всё равно';

  @override
  String get lockedTitle => 'Активация';

  @override
  String get lockedHeadline => 'Добро пожаловать!';

  @override
  String get lockedBody =>
      'Оформите подписку или введите промокод — и подключайтесь в один тап.';

  @override
  String get lockedCta => 'Оформить подписку или введите промокод';

  @override
  String get lockedRefreshAccess => 'Обновить доступ';

  @override
  String get settingsSupport => 'Поддержка';

  @override
  String get settingsSupportHint => 'Telegram — перенос после переустановки';

  @override
  String get lockedPay1m => 'Оплатить 1 месяц';

  @override
  String get lockedPay3m => 'Оплатить 3 месяца';

  @override
  String get lockedOrPromo => 'Или введите промокод';

  @override
  String get lockedPayFailed =>
      'Не удалось начать оплату. Попробуйте снова или напишите в поддержку.';

  @override
  String get lockedPayReturnTitle => 'Оплата открыта';

  @override
  String get lockedPayReturnBody =>
      'После оплаты в браузере нажмите «Проверить доступ».';

  @override
  String get lockedPayReturnCheck => 'Проверить доступ';

  @override
  String get recoveryCodeTitle => 'Код восстановления';

  @override
  String get recoveryCodeHeadline => 'Код восстановления';

  @override
  String get recoveryCodeBody =>
      'Опционально для поддержки. Основной путь — номер платежа.';

  @override
  String get recoveryCodeCopy => 'Скопировать';

  @override
  String get recoveryCodeCopied => 'Код скопирован';

  @override
  String get recoveryCodeConfirm => 'Продолжить';

  @override
  String get recoveryCodeContinue => 'Продолжить';

  @override
  String get restoreTitle => 'Восстановить доступ';

  @override
  String get restoreHeadline => 'Введите номер платежа';

  @override
  String get restoreBody =>
      'После переустановки вставьте ID платежа Platega из СМС банка или чека. Код сохранения не нужен.';

  @override
  String get restorePaymentLabel => 'Номер платежа';

  @override
  String get restorePaymentHint => 'UUID из чека / СМС';

  @override
  String get restorePaymentEmpty => 'Введите номер платежа';

  @override
  String get restorePaymentNotFound => 'Платёж не найден. Проверьте номер.';

  @override
  String get restorePaymentNotConfirmed => 'Этот платёж ещё не подтверждён.';

  @override
  String get restoreCodeLabel => 'Код восстановления';

  @override
  String get restoreCodeHint => 'TRM-XXXX-XXXX-XXXX';

  @override
  String get restoreCodeEmpty => 'Введите код восстановления';

  @override
  String get restoreSubmit => 'Восстановить';

  @override
  String get restoreInvalid => 'Неверный код восстановления';

  @override
  String get restoreFailed =>
      'Не удалось восстановить доступ. Попробуйте снова.';

  @override
  String get restoreSettingsHint => 'После переустановки — код восстановления';

  @override
  String get restoreHeadlineCode => 'Введите код восстановления';

  @override
  String get restoreBodyCode =>
      'После переустановки введите код, показанный при первом запуске.';

  @override
  String get settingsInviteDevice => 'Пригласить устройство';

  @override
  String get settingsInviteDeviceHint => 'Создать короткий код места';

  @override
  String get settingsAcceptSeat => 'Ввести код места';

  @override
  String get settingsAcceptSeatHint => 'Присоединиться к аккаунту';

  @override
  String get settingsSeatCodeTitle => 'Код места';

  @override
  String get settingsSeatCodeCopied => 'Код скопирован';

  @override
  String get settingsRecoverAccess => 'Восстановить доступ';

  @override
  String get settingsRecoverAccessHint =>
      'Код восстановления после переустановки';

  @override
  String get bootstrapFailed => 'Не удалось начать сессию. Проверьте связь.';
}
