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
  String get loginTestButton => 'Войти (тестовая кнопка)';

  @override
  String get loginErrorTimeout => 'Нет ответа от сервера';

  @override
  String get loginErrorNetwork => 'Нет связи с сервером';

  @override
  String get loginErrorGeneric => 'Не удалось выполнить запрос';

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
  String get homeQuotaUnlimitedTeaser => 'Безлимит с Premium';

  @override
  String get homeQuotaUnlimitedCta => 'Подключить безлимит';

  @override
  String get homeTrafficExhausted => 'Трафик закончился';

  @override
  String homeTrafficAmount(String remaining, String limit) {
    return '$remaining / $limit ГБ';
  }

  @override
  String get homeNoVpnRow => 'Что работает без VPN?';

  @override
  String get premiumHeadline => 'Расширенные локации';

  @override
  String get premiumBody =>
      'Премиум открывает дополнительные локации, до 5 устройств и снимает лимит 4,20 ГБ.';

  @override
  String get premiumFeatureYt => 'Дополнительные локации для просмотра';

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
      'Тарифы и промокоды. Премиум открывает дополнительные локации.';

  @override
  String get subscriptionPay => 'Оплатить';

  @override
  String get locationsPremiumLocked => 'Премиум';

  @override
  String get locationsPremiumUnavailable => 'Доступно в Premium';

  @override
  String get settingsNoVpn => 'Что работает без VPN?';

  @override
  String get settingsNoVpnHint => 'Сайты, которые идут мимо VPN';

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
  String get homePathIncompatibleHint =>
      'Не вышло проверить сервер. Нажмите ещё раз или выберите локацию вручную.';

  @override
  String get homeQuotaExceededTitle => 'Лимит Free исчерпан';

  @override
  String get homeQuotaExceededHint =>
      'В этом месяце израсходованы 4,20 ГБ. Оформите Premium — без лимита трафика.';

  @override
  String get homeQuotaUpgradeCta => 'Оформить Premium';

  @override
  String get homeTtProvisionFailedTitle => 'Сервер недоступен';

  @override
  String get homeTtProvisionFailedHint =>
      'Не удалось подготовить эту локацию. Попробуйте позже или выберите другую.';

  @override
  String get homeVpnProbeFailedTitle => 'Сервер не отвечает';

  @override
  String homeVpnProbeFailedHint(String node) {
    return 'Локация $node временно недоступна. Выберите другую в «Локации» или повторите позже.';
  }

  @override
  String get homeVpnConflictTitle => 'Мешает другой VPN';

  @override
  String get homeVpnConflictHint =>
      'Отключите другой VPN в настройках Android, затем подключитесь снова.';

  @override
  String get homeVpnConflictHintIos =>
      'Отключите другой VPN в Настройках → VPN.';

  @override
  String homeVpnConflictHintNamed(String app) {
    return 'Отключите «$app» в настройках Android, затем подключитесь снова.';
  }

  @override
  String homeVpnConflictHintNamedIos(String app) {
    return 'Отключите «$app» в Настройках → VPN.';
  }

  @override
  String get homeVpnPermissionHint =>
      'Разрешите VPN в системном запросе Android, затем нажмите подключение снова.';

  @override
  String get homeVpnPermissionHintIos =>
      'Разрешите VPN в системном запросе, затем подключитесь снова.';

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
  String get settingsSubscription => 'Доступ';

  @override
  String get settingsSubscriptionActive => 'Активна';

  @override
  String get settingsProBadge => 'PRO';

  @override
  String get settingsActiveBadge => 'Активна';

  @override
  String get settingsAccessEarlyTitle => 'Премиум';

  @override
  String get settingsAccessEarlySubtitle => 'Доступ по приглашению.';

  @override
  String get settingsAccessBetaTitle => 'Премиум';

  @override
  String get settingsAccessBetaSubtitle =>
      'Доступ по приглашению · без лимита Free.';

  @override
  String get settingsAccessNoneTitle => 'Нет доступа';

  @override
  String get settingsAccessNoneSubtitle => 'Нужен код приглашения.';

  @override
  String get settingsAccessFreeTitle => 'Бесплатный';

  @override
  String get settingsAccessFreeSubtitle => '1 устройство · до 4,20 ГБ в месяц.';

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
  String get settingsSubscriptionAlpha => 'Премиум';

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
  String get settingsKillSwitchOpenVpn => 'Открыть настройки VPN';

  @override
  String get settingsKillSwitchOpenFailed =>
      'Не удалось открыть настройки VPN. Откройте Настройки → Сеть и интернет → VPN.';

  @override
  String get settingsKillSwitchOpenFailedIos =>
      'Не удалось открыть настройки VPN. Откройте Настройки → VPN.';

  @override
  String get settingsAutoReconnect => 'Авто-переподключение';

  @override
  String get settingsAutoReconnectHint => 'Быстрое переподключение при обрыве';

  @override
  String get settingsDevices => 'Устройства';

  @override
  String get settingsDevicesHint =>
      'Зарегистрированные установки и отзыв доступа';

  @override
  String get devicesTitle => 'Устройства';

  @override
  String get devicesHint =>
      'Можно выйти с других устройств, если нет к ним доступа.';

  @override
  String devicesCreated(String date) {
    return 'Создано: $date';
  }

  @override
  String get devicesCurrentDevice => 'Это устройство';

  @override
  String get devicesSectionThis => 'Эта установка';

  @override
  String get devicesSectionGroup => 'В группе';

  @override
  String get devicesSectionActions => 'Группа';

  @override
  String get devicesInGroupLabel => 'В группе';

  @override
  String devicesGroupEmpty(int count) {
    return 'Пока одно устройство · ещё $count мест';
  }

  @override
  String get devicesLimitReached => 'Лимит устройств достигнут';

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
  String get devicesRename => 'Переименовать';

  @override
  String get devicesRenameTitle => 'Имя устройства';

  @override
  String get devicesRenameHint => 'Так оно будет видно в списке';

  @override
  String get devicesRenameSave => 'Сохранить';

  @override
  String get devicesRenamed => 'Имя обновлено';

  @override
  String get devicesRenameFailed => 'Не удалось переименовать';

  @override
  String get devicesThisDevice => 'Вы';

  @override
  String get devicesOwnerLabel => 'Владелец подписки';

  @override
  String get devicesInvitedLabel => 'Приглашённое устройство';

  @override
  String get devicesRevoke => 'Удалить';

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
  String get devicesLeaveHint =>
      'Это устройство станет отдельным бесплатным аккаунтом';

  @override
  String get devicesLeave => 'Покинуть чужую подписку';

  @override
  String get devicesLeaveTitle => 'Покинуть чужую подписку?';

  @override
  String get devicesLeaveBody =>
      'Это устройство станет отдельным бесплатным аккаунтом. Оплаченная подписка останется у владельца. Сохраните новый код восстановления, если он появится.';

  @override
  String get devicesLeaveConfirm => 'Покинуть';

  @override
  String get devicesLeft => 'Устройство отвязано от аккаунта';

  @override
  String get devicesLeaveFailed => 'Не удалось покинуть аккаунт';

  @override
  String get devicesLogoutAll => 'Выйти на всех устройствах';

  @override
  String get devicesLogoutAllHint =>
      'Отозвать все устройства аккаунта, включая это устройство';

  @override
  String get devicesLogoutAllTitle => 'Выйти на всех устройствах?';

  @override
  String get devicesLogoutAllBody =>
      'Все устройства этого аккаунта потеряют доступ, включая это устройство. Нужно будет восстановить аккаунт по коду или зарегистрироваться заново.';

  @override
  String get devicesLogoutAllConfirm => 'Выйти везде';

  @override
  String get devicesLogoutAllFailed => 'Не удалось выйти на всех устройствах';

  @override
  String get devicesLimitOpenManage => 'Управление устройствами';

  @override
  String get splitTunnelSearchHint => 'Поиск по моим сайтам';

  @override
  String get splitTunnelBundledSection => 'Готовый список';

  @override
  String get splitTunnelBundledLead =>
      'Сайты из списка открываются обычным интернетом, не через защиту. Остальное — через Теремок.';

  @override
  String get splitTunnelBundledRuTitle => 'Готовые списки';

  @override
  String get splitTunnelBundledRuSubtitle =>
      'VK, Яндекс, маркетплейсы, MAX и другие — одним касанием';

  @override
  String get splitTunnelBundledInfoTitle => 'Как это работает';

  @override
  String get splitTunnelBundledInfoBody =>
      'Сайты из списка открываются обычным интернетом, не через защиту. Остальное по-прежнему через Теремок.\n\nНа iPhone нельзя вытащить из VPN целое приложение — только сайт по адресу. В Safari обычно срабатывает. Приложение банка или маркетплейса может остаться в VPN: у них свои адреса.\n\nКрупные сервисы сидят на куче серверов. Часть страниц или видео может идти через защиту, даже если тумблер включён. Если сайт должен быть под защитой — выключите его здесь.\n\nПосле изменения нажмите «Переподключить».';

  @override
  String get splitTunnelBundledInfoClose => 'Понятно';

  @override
  String get splitTunnelSitesLead =>
      'Сайты из списка открываются обычным интернетом, не через защиту. Остальное — через Теремок.';

  @override
  String get splitTunnelSitesIosNote =>
      'На iPhone из VPN выходит только точный hostname (не все поддомены). Целое приложение вытащить нельзя.';

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
      'Добавьте точный hostname — без VPN пойдёт только он, не его поддомены.';

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
  String get splitTunnelAppsLockdownWarning =>
      'Включён Android «Блокировать без VPN». Приложения из этого списка могут остаться без интернета, пока вы не выключите блокировку или не вернёте их в VPN.';

  @override
  String get splitTunnelGeoHy2Pending =>
      'Пока не применяется (нужны IP-списки). Используйте вкладку «Приложения» или добавьте сайт.';

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
  String get tunnelLogsTitle => 'Логи туннеля';

  @override
  String get tunnelLogsLevelOff => 'Выключены';

  @override
  String get tunnelLogsLevelError => 'Ошибки';

  @override
  String get tunnelLogsLevelWarn => 'Предупреждения';

  @override
  String get tunnelLogsLevelInfo => 'Информация';

  @override
  String get tunnelLogsLevelDebug => 'Отладка';

  @override
  String get tunnelLogsSearch => 'Текст, IP или домен';

  @override
  String get tunnelLogsAll => 'Все';

  @override
  String get tunnelLogsSession => 'Сессия';

  @override
  String get tunnelLogsNetwork => 'Сеть';

  @override
  String get tunnelLogsRefresh => 'Обновить';

  @override
  String get tunnelLogsCopy => 'Копировать';

  @override
  String get tunnelLogsExport => 'Экспорт всех';

  @override
  String get tunnelLogsDelete => 'Удалить';

  @override
  String get tunnelLogsCopied => 'Лог скопирован';

  @override
  String get tunnelLogsEmpty => 'Записей нет';

  @override
  String get settingsSendReportHint =>
      'Копирует диагностику. Вставьте её в поддержку сами.';

  @override
  String get settingsSendReportConfirm => 'Отправить';

  @override
  String get settingsReportSent =>
      'Отчёт ушёл в поддержку через бота. Текст также скопирован.';

  @override
  String get settingsReportCopied => 'Текст отчёта скопирован';

  @override
  String settingsReportSaved(String id) {
    return 'Отчёт сохранён: $id. Скопирован в буфер.';
  }

  @override
  String get settingsReportFailed => 'Не удалось собрать отчёт';

  @override
  String get settingsReportTelegramFailed =>
      'Не удалось отправить через бота. Текст отчёта скопирован.';

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
      'Карточка с кнопкой «Отключить». Выключите — карточка спрячется, VPN останется.';

  @override
  String get settingsQsTileTitle => 'Плитка в шторке';

  @override
  String get settingsQsTileHint =>
      'Добавить плитку: включение и отключение из панели быстрых настроек';

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
  String get settingsQsTileNotAdded => 'Плитка не добавлена';

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
  String get regionAutoSubtitle => 'Ближайшая локация';

  @override
  String get regionSelected => 'Выбрано';

  @override
  String get regionSectionServers => 'Серверы';

  @override
  String get regionSectionGeneral => 'Общего назначения';

  @override
  String get regionSectionYoutube => 'Премиум';

  @override
  String get regionSectionYoutubeIos => 'Сервис';

  @override
  String get regionSectionFree => 'Бесплатно';

  @override
  String get regionSectionEurope => 'Латвия';

  @override
  String get regionSectionUsa => 'США';

  @override
  String get regionComingSoon => 'Скоро появится';

  @override
  String get regionComingSoonBadge => 'Скоро';

  @override
  String get regionSectionOffline => 'Недоступные серверы';

  @override
  String get regionOnline => 'онлайн';

  @override
  String get regionBlurbFree => 'Сайты и сервисы';

  @override
  String get regionBlurbGaming => 'Низкий пинг';

  @override
  String get regionBlurbYoutube => 'Комфортный просмотр';

  @override
  String get regionBlurbIndia => 'Сервисы';

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
  String get regionSwitchingTitle => 'Меняем локацию…';

  @override
  String get regionSwitchingBody => 'Подключаем выбранный сервер';

  @override
  String get regionSwitchedTitle => 'Готово';

  @override
  String get regionSwitchFailedTitle => 'Не удалось сменить локацию';

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
  String get navBack => 'Назад';

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
      'Аккаунт создаётся сам. Дальше один тап — защищённое соединение.';

  @override
  String get welcomeContinue => 'Продолжить';

  @override
  String get welcomeSkip => 'Пропустить';

  @override
  String get promoTitle => 'Код доступа';

  @override
  String get promoHeadline => 'Введите персональный код';

  @override
  String get promoBody => 'Если есть код — введите его здесь.';

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
  String get referralShareTitle => 'Пригласить друга';

  @override
  String get referralShareBody =>
      'Друг вводит код после установки. Дни вам капают после его оплаты, не после установки.';

  @override
  String get referralCopy => 'Скопировать ссылку';

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
  String get onboardingConnectBodyIos =>
      'На главном экране нажмите «Подключиться». iPhone один раз спросит разрешение VPN — так и должно быть.';

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
  String get betaGateChecking => 'Проверяем доступ…';

  @override
  String get betaGateErrorTimeout =>
      'Сервер не ответил. Если VPN включён — отключите его и повторите.';

  @override
  String get betaGateErrorUnauthorized => 'Сессия устарела. Повторите вход.';

  @override
  String get betaGateDisconnectVpnRetry => 'Отключить VPN и повторить';

  @override
  String get betaGateContinueAnyway => 'Продолжить всё равно';

  @override
  String get lockedTitle => 'Активация';

  @override
  String get lockedHeadline => 'Добро пожаловать!';

  @override
  String get lockedBody => 'Оформите подписку — и подключайтесь в один тап.';

  @override
  String get lockedCta => 'Оформить подписку или введите промокод';

  @override
  String get lockedRefreshAccess => 'Обновить доступ';

  @override
  String get settingsSupport => 'Поддержка';

  @override
  String get settingsSupportHint => 'Telegram — перенос после переустановки';

  @override
  String get settingsSupportHintIos => 'Вопросы в Telegram-боте';

  @override
  String get lockedPay1m => 'Оплатить 1 месяц';

  @override
  String get lockedPay3m => 'Оплатить 3 месяца';

  @override
  String get lockedPlan1m => '1 месяц';

  @override
  String get lockedPlan3m => '3 месяца';

  @override
  String get lockedPlan6m => '6 месяцев';

  @override
  String get lockedPlan12m => '12 месяцев';

  @override
  String lockedPayAmount(int price) {
    return 'Оплатить $price ₽';
  }

  @override
  String lockedPerMonth(int price) {
    return '$price ₽/мес';
  }

  @override
  String lockedSavePercent(int percent) {
    return '−$percent%';
  }

  @override
  String lockedVerifyCode(String code) {
    return 'Код проверки: $code';
  }

  @override
  String get settingsTerms => 'Соглашение';

  @override
  String get settingsPricing => 'Тарифы';

  @override
  String get settingsDeleteAccount => 'Удаление аккаунта';

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
      'Сохраните код — понадобится после переустановки. Без кода можно восстановить через Telegram.';

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
  String get restoreHeadline => 'Восстановить доступ';

  @override
  String get restoreBody => 'Введите код восстановления или откройте Telegram.';

  @override
  String get restoreBodyIos =>
      'Введите код восстановления или откройте Telegram.';

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
  String get restoreDeviceLimitTitle => 'Лимит устройств';

  @override
  String get restoreDeviceLimitBody =>
      'Выберите, какое устройство отключить, чтобы войти с этого устройства.';

  @override
  String get restoreAccountFull =>
      'Лимит устройств. Удалите лишнее в списке устройств, затем войдите снова. Уже подключённые остались в сети.';

  @override
  String get restoreDeviceLimitOwner => 'Владелец';

  @override
  String get restoreDeviceLimitPickFailed =>
      'Не удалось освободить слот. Попробуйте снова.';

  @override
  String get restoreSettingsHint => 'После переустановки — код восстановления';

  @override
  String get restoreHeadlineCode => 'Введите код восстановления';

  @override
  String get restoreBodyCode =>
      'После переустановки введите код восстановления или откройте Telegram.';

  @override
  String get restoreBodyCodeIos =>
      'После переустановки введите код восстановления или откройте Telegram.';

  @override
  String get settingsInviteDevice => 'Добавить устройство в подписку';

  @override
  String get settingsInviteDeviceHint => 'Код для входа в группу';

  @override
  String get settingsAcceptSeat => 'Войти в группу';

  @override
  String get settingsAcceptSeatHint => 'Присоединиться по приглашению';

  @override
  String get settingsSeatCodeTitle => 'Код приглашения';

  @override
  String get settingsSeatCodeCopied => 'Код скопирован';

  @override
  String get settingsSeatInviteFailed => 'Не удалось создать код приглашения';

  @override
  String get settingsAcceptSeatOk => 'Устройство добавлено в группу';

  @override
  String get settingsSeatPremiumRequired =>
      'Добавление устройств доступно в Premium';

  @override
  String get settingsSeatCodeNotFound => 'Код не найден или истёк';

  @override
  String get settingsSeatDeviceLimit => 'Достигнут лимит устройств на подписке';

  @override
  String get settingsSeatOwnCode =>
      'Нельзя принять свой код — введите его на другом устройстве';

  @override
  String get settingsSeatAcceptFailed => 'Не удалось войти в группу';

  @override
  String get settingsSeatCodeTtl => 'Код действует 30 минут';

  @override
  String get settingsSeatShowQr => 'Показать код';

  @override
  String get settingsSeatScanHint =>
      'Отсканируйте QR-код или перейдите по ссылке';

  @override
  String get settingsPayOwnerOnly => 'Оплату оформляет владелец подписки';

  @override
  String get settingsSeatForbidden =>
      'Это может сделать только владелец подписки';

  @override
  String get seatAcceptConsentTitle => 'Войти в эту группу?';

  @override
  String get seatAcceptConsentBody =>
      'Владелец аккаунта увидит имя устройства, платформу и дату добавления. Выйти из группы можно позже.';

  @override
  String get seatAcceptConsentConfirm => 'Войти';

  @override
  String get devicesOwnerCannotLeave => 'Сначала отзовите другие устройства';

  @override
  String get settingsRecoverAccess => 'Восстановить доступ';

  @override
  String get settingsRecoverAccessHint =>
      'Код восстановления после переустановки';

  @override
  String get bootstrapFailed => 'Не удалось начать сессию. Проверьте связь.';

  @override
  String get accountHubTitle => 'Аккаунт';

  @override
  String get accountHubGuestLead =>
      'Аккаунт на этом устройстве. Код восстановления — после переустановки. Telegram — тот же аккаунт.';

  @override
  String get accountHubLinkedLead =>
      'Telegram привязан. Бот — тот же аккаунт: подписка и восстановление.';

  @override
  String get accountHubLinkedLeadIos =>
      'Telegram привязан. Бот — тот же аккаунт и восстановление.';

  @override
  String get accountHubRecoveryMissing =>
      'Код на этом телефоне уже сохраняли. После переустановки откройте Telegram с тем же аккаунтом.';

  @override
  String get accountHubLinkTelegram => 'Telegram';

  @override
  String get accountHubLinkTelegramHint => 'Подписка и восстановление в боте';

  @override
  String get accountHubLinkEmail => 'Почта';

  @override
  String get accountHubLinkEmailHint => 'Привязать по коду из письма';

  @override
  String get accountHubRecovery => 'Код восстановления';

  @override
  String get accountHubRecoveryHint =>
      'Восстановить доступ после переустановки';

  @override
  String get accountHubRecoverySaveBanner =>
      'Сохраните код восстановления — он понадобится после переустановки.';

  @override
  String get accountHubRecoverySaveCta => 'Сохранить код';

  @override
  String get accountHubPromo => 'Промокод';

  @override
  String get accountHubPromoHint => 'Активировать код';

  @override
  String get accountHubAccessSection => 'Ваш доступ';

  @override
  String get accountHubContact => 'Контакт';

  @override
  String get accountHubLoadError => 'Не удалось загрузить аккаунт';

  @override
  String get accountTelegramLead =>
      'Откройте бота и подтвердите привязку. Вернитесь в приложение — статус обновится автоматически.';

  @override
  String get accountTelegramOpenBot => 'Открыть Telegram';

  @override
  String get accountTelegramWaiting => 'Ждём подтверждения…';

  @override
  String get accountTelegramWaitingHint =>
      'После /start в боте вернитесь сюда.';

  @override
  String get accountTelegramStartFailed =>
      'Не удалось начать привязку Telegram';

  @override
  String get accountTelegramVpnRequired => 'Сначала подключитесь.';

  @override
  String get restoreTelegramCta => 'Восстановить через Telegram';

  @override
  String get restoreTelegramVpnRequired => 'Сначала подключитесь.';

  @override
  String get homeTelegramRestoreCta =>
      'Уже был Теремок? Восстановите через Telegram';

  @override
  String get homeTelegramRestoreConnectFirst => 'Сначала подключитесь.';

  @override
  String get accountEmailLead => 'Укажите почту — пришлём одноразовый код.';

  @override
  String get accountEmailLabel => 'Email';

  @override
  String get accountEmailSendCode => 'Отправить код';

  @override
  String get accountEmailCodeLabel => 'Код из письма';

  @override
  String get accountEmailVerify => 'Подтвердить';

  @override
  String get accountEmailChangeAddress => 'Другой адрес';

  @override
  String get accountEmailInvalid => 'Введите корректный email';

  @override
  String get accountEmailSendFailed => 'Не удалось отправить код';

  @override
  String get accountEmailCodeRequired => 'Введите код из письма';

  @override
  String get accountEmailVerifyFailed => 'Неверный или просроченный код';

  @override
  String get accountEmailDebugHint => 'DEBUG: код подставлен из ответа API';

  @override
  String get navPromo => 'Код доступа';

  @override
  String get iosBillingUnavailableBody =>
      'Оплата в приложении недоступна. Бесплатные локации работают.';

  @override
  String get iosAdvancedFeaturesCta => 'Расширенные возможности';

  @override
  String get vpnDisclosureTitle => 'Защищённое соединение';

  @override
  String get vpnDisclosureLead =>
      'Перед первым подключением коротко объясняем, как работает VPN в Теремке и какие данные нужны для сервиса.';

  @override
  String get vpnDisclosureVpnTitle => 'Зачем нужен VPN на Android';

  @override
  String get vpnDisclosureVpnBody =>
      'Приложение использует системный VPNService, чтобы создать защищённый туннель после нажатия «Подключиться». Трафик приложений на устройстве направляется через этот туннель к серверам Teremok VPN. Это основная функция приложения — обеспечить защищённое соединение, а не доступ к корпоративной сети.';

  @override
  String get vpnDisclosureVpnTitleIos => 'Зачем нужна конфигурация VPN';

  @override
  String get vpnDisclosureVpnBodyIos =>
      'Приложение использует системное Network Extension (Packet Tunnel), чтобы создать защищённый туннель после нажатия «Подключиться». Трафик устройства направляется через этот туннель к серверам Teremok VPN. Это основная функция — защищённое соединение в публичных сетях, а не доступ к корпоративной сети и не маркетинг «обхода».';

  @override
  String get vpnDisclosureDataTitle => 'Какие данные мы обрабатываем';

  @override
  String get vpnDisclosureDataBody =>
      'Идентификатор установки (device ID) и идентификатор аккаунта — чтобы выдать доступ и восстановить его после переустановки. История покупок подписки (через платёжного провайдера; номер карты мы не храним). По вашей инициативе — диагностический отчёт из Настроек. Агрегированная сводка использования (попытки подключения, длительность сессии) — без истории сайтов.';

  @override
  String get vpnDisclosureDataBodyIos =>
      'Идентификатор установки (device ID) и идентификатор аккаунта — чтобы выдать доступ и восстановить его после переустановки. По вашей инициативе — диагностический отчёт из Настроек. Агрегированная сводка использования (попытки подключения, длительность сессии) — без истории сайтов. Мы не продаём трафик туннеля и не монетизируем пакеты других приложений.';

  @override
  String get vpnDisclosureNotTitle => 'Чего мы не делаем';

  @override
  String get vpnDisclosureNotBody =>
      'Не ведём историю посещённых сайтов и не используем рекламный идентификатор. Не монетизируем трафик других приложений через подмену рекламы.';

  @override
  String get vpnDisclosureAccept => 'Принимаю и продолжить';

  @override
  String get vpnDisclosureDecline => 'Не сейчас';

  @override
  String accountTelegramLinkedTitle(String handle) {
    return '$handle привязан';
  }

  @override
  String get accountTelegramLinkedBody =>
      'После переустановки доступ восстанавливается через этот Telegram. Подписка тоже в боте.';

  @override
  String get accountTelegramOwnerRestoredTitle => 'Аккаунт восстановлен';

  @override
  String get accountTelegramOwnerRestoredBody =>
      'Теперь можно управлять подпиской и восстанавливать доступ через Telegram.';

  @override
  String get accountTelegramMemberRestoredTitle => 'Вернулись в подписку';

  @override
  String get accountTelegramMemberRestoredBody =>
      'Владелец не изменился. Доступ подтянется в приложении.';

  @override
  String get accountTelegramDone => 'Готово';

  @override
  String get restoreTelegramSlotRevoked =>
      'Владелец удалил это устройство. Попросите новый код приглашения.';

  @override
  String get restoreTelegramSubscriptionInactive =>
      'Подписка сейчас не активна. После продления место можно восстановить снова.';

  @override
  String get freeAdd => 'Добавить';

  @override
  String get freePaste => 'Вставить';

  @override
  String get freeQr => 'QR';

  @override
  String get freeAddServer => 'Добавить сервер';

  @override
  String get freeEmptyTitle => 'Нет добавленных серверов';

  @override
  String get freeEmptyBody => 'Добавьте ссылку, ключ или QR-код.';

  @override
  String get freeStatus => 'Статус';

  @override
  String get freeProfile => 'Профиль';

  @override
  String get freeProtocol => 'Протокол';

  @override
  String get freeUptime => 'Время';

  @override
  String get freeNoProfile => 'Нет';

  @override
  String get freeAddTitle => 'Добавить';

  @override
  String get freeAddHint =>
      'Вставьте ссылку или ключ. В приложении ничего не продаётся.';

  @override
  String get freeSaveConnect => 'Сохранить и подключить';

  @override
  String get freeSaveOnly => 'Только сохранить';

  @override
  String get freePreview => 'Найдено';

  @override
  String get freeServerAdded => 'Сервер добавлен';

  @override
  String get freeLinkInvalid => 'Ссылка не разобрана';

  @override
  String get freeOnboardTitle => 'Бесплатное приложение';

  @override
  String get freeOnboardBody =>
      'Без рекламы. Внутри ничего не продаётся. Подключение — по ссылке, которую добавляете вы.';

  @override
  String get freeOnboardAddTitle => 'Добавьте ссылку, ключ или QR';

  @override
  String get freeOnboardAddBody =>
      'Серверы из этой ссылки появятся в списке. Какой использовать — выбираете вы.';

  @override
  String get freeOnboardConnectTitle => 'Подключайтесь одним нажатием';

  @override
  String get freeOnboardConnectBody =>
      'Нажмите на домик, чтобы включить или выключить. Статус остаётся на этом экране.';

  @override
  String get freeLater => 'Позже';

  @override
  String get freeBatteryTitle => 'Не останавливать туннель';

  @override
  String get freeBatteryBody =>
      'Android может остановить туннель, чтобы экономить батарею. Можно разрешить работу в фоне.';

  @override
  String get freeBatteryAllow => 'Разрешить';

  @override
  String get freeBatteryDismiss => 'Больше не спрашивать';

  @override
  String get freeServers => 'Сервера';

  @override
  String get freeSearch => 'Поиск серверов';

  @override
  String get freeDelete => 'Удалить';
}
