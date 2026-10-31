// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppL10nRu extends AppL10n {
  AppL10nRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Прокси Дом';

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
  String get homeTitle => 'Прокси Дом';

  @override
  String get homeVpnHint => 'Интерфейс туннеля — в шагах 9+';

  @override
  String get homeDisconnected => 'Не подключено';

  @override
  String get homeConnecting => 'Подключение...';

  @override
  String get homeConnected => 'Подключено';

  @override
  String get homeTapHint => 'Нажмите, чтобы подключиться';

  @override
  String get homeConnectingHint => 'Подключаемся…';

  @override
  String get homeConnectedHint => 'Подключено';

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
  String get navVpn => 'Подключение';

  @override
  String get navLocations => 'Локации';

  @override
  String get navModes => 'Режимы';

  @override
  String get homeTrafficRemainder => 'Остаток трафика';

  @override
  String get homeTrafficExhausted => 'Трафик закончился';

  @override
  String get homeTrafficLabel => 'ТРАФИК';

  @override
  String get homeAddServer => 'Добавить сервер';

  @override
  String get homeMetricTime => 'Время';

  @override
  String get homeMetricSpeed => 'Скорость';

  @override
  String get homeMetricTraffic => 'Трафик';

  @override
  String get homeTrafficUnlimited => 'БЕЗ ЛИМИТА';

  @override
  String get profileTrafficRemaining => 'осталось';

  @override
  String get profileTrafficUsed => 'использовано';

  @override
  String get profileTrafficNoData => 'нет данных о лимите';

  @override
  String get profileTrafficStale => 'устарело';

  @override
  String get profileTrafficExpires => 'истекает';

  @override
  String get profileSourceLocal => 'локальный импорт';

  @override
  String homeTrafficAmount(String remaining, String limit) {
    return '$remaining / $limit ГБ';
  }

  @override
  String get homeNoVpnRow => 'Маршрутизация';

  @override
  String get settingsNoVpn => 'Маршрутизация';

  @override
  String get settingsNoVpnHint =>
      'Правила раздельного туннеля для приложений и сайтов';

  @override
  String get modesTitle => 'Режим';

  @override
  String get modesSubtitle => 'Как работает туннель';

  @override
  String get modeSmartTitle => 'Умный режим';

  @override
  String get modeSmartBody =>
      'Ресурсы российских филиалов идут напрямую, остальной трафик — через выбранный узел.';

  @override
  String get modeSmartBadge => 'АВТО';

  @override
  String get modeFullTitle => 'Полный туннель';

  @override
  String get modeFullBody =>
      'Весь трафик идёт через выбранный узел. Просто и предсказуемо.';

  @override
  String get modeSitesTitle => 'По сайтам';

  @override
  String get modeSitesBody =>
      'Через туннель пойдут только выбранные сайты. Остальное — напрямую.';

  @override
  String get modesVpnOffTitle => 'Туннель выключен';

  @override
  String get modesVpnOffBody => 'Подключите туннель, чтобы режимы заработали';

  @override
  String get modesConfirmFullTitle => 'Перейти в режим полного туннеля?';

  @override
  String get modesConfirmFullBody =>
      'В этом режиме весь трафик идёт через выбранный узел. Внутренние сервисы и российские ресурсы могут стать медленнее.\n\nЧтобы они работали напрямую — используйте Умный режим.';

  @override
  String get modesConfirmFullCancel => 'Не переключать';

  @override
  String get modesConfirmFullOk => 'Переключить';

  @override
  String get modesSitesSectionSmart => 'Дополнительно напрямую';

  @override
  String get modesSitesSectionSites => 'Сайты через туннель';

  @override
  String get modesSitesCustomSection => 'Свои сайты';

  @override
  String get modesSitesCustomHint => 'gw.company-net.ru';

  @override
  String get modesSitesAllowlistHint =>
      'Через туннель пойдут только выбранные сайты — остальной трафик идёт напрямую и на полной скорости.';

  @override
  String get modesLocationTitle => 'Локация';

  @override
  String get modesLocationHint => 'Сервер и страна';

  @override
  String get modesPendingTitle => 'Нужно переподключить туннель';

  @override
  String get modesPendingBody =>
      'Изменения маршрутизации применятся после переподключения.';

  @override
  String get modesReconnect => 'Переподключить';

  @override
  String get modesReconnectingTitle => 'Переподключаем туннель…';

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
  String get homeStatPingPending => 'измеряем';

  @override
  String get homeLinkOnline => 'Подключено';

  @override
  String get homeLinkOffline => 'Нет подключения';

  @override
  String get homeLinkLabel => 'Связь';

  @override
  String get homeStatDownload => 'Скачивание';

  @override
  String get homeStatUpload => 'Отправка';

  @override
  String get homeMoreMenu => 'Ещё';

  @override
  String get homeRetry => 'Повторить';

  @override
  String get homeErrorFriendly => 'Не удалось подключиться. Попробуйте снова.';

  @override
  String get homeNodeAuthRefused =>
      'Узел отклонил аутентификацию. Сессия не разрешена: трафик периода закончился или ключ отозван.';

  @override
  String get homePathIncompatibleHint =>
      'Не вышло проверить сервер. Нажмите ещё раз или выберите локацию вручную.';

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
  String get homeVpnConflictTitle => 'Мешает другое туннельное подключение';

  @override
  String get homeVpnConflictHint =>
      'Отключите другое туннельное подключение в настройках Android, затем подключитесь снова.';

  @override
  String get homeVpnConflictHintIos =>
      'Отключите другое туннельное подключение в Настройках → VPN.';

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
      'Разрешите туннель в системном запросе Android, затем нажмите подключение снова.';

  @override
  String get homeVpnPermissionHintIos =>
      'Разрешите туннель в системном запросе, затем подключитесь снова.';

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
  String get settingsProBadge => 'PRO';

  @override
  String get settingsActiveBadge => 'Активна';

  @override
  String get settingsServerRegion => 'Регион сервера';

  @override
  String get settingsProtocol => 'Протокол';

  @override
  String get settingsProtocolLocked => 'Сейчас доступен только VLESS + Reality';

  @override
  String get settingsKillSwitchOpenVpn => 'Открыть настройки туннеля';

  @override
  String get settingsKillSwitchOpenFailed =>
      'Не удалось открыть настройки туннеля. Откройте Настройки → Сеть и интернет → VPN.';

  @override
  String get settingsKillSwitchOpenFailedIos =>
      'Не удалось открыть настройки туннеля. Откройте Настройки → VPN.';

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
      'Пока нет устройств — подключите туннель, чтобы зарегистрировать это.';

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
  String get devicesInvitedLabel => 'Приглашённое устройство';

  @override
  String get devicesRevoke => 'Удалить';

  @override
  String get devicesRevokeTitle => 'Отозвать устройство?';

  @override
  String get devicesRevokeBody =>
      'Туннельный ключ этого устройства перестанет работать. Остальные устройства не затронуты.';

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
      'Сайты из списка открываются обычным интернетом, не через защиту. Остальное — через Прокси Дом.';

  @override
  String get splitTunnelBundledRuTitle => 'Готовые списки';

  @override
  String get splitTunnelBundledRuSubtitle =>
      'VK, Яндекс, маркетплейсы, MAX и другие — одним касанием';

  @override
  String get splitTunnelBundledInfoTitle => 'Как это работает';

  @override
  String get splitTunnelBundledInfoBody =>
      'Сайты из списка открываются обычным интернетом, не через защиту. Остальное по-прежнему через Прокси Дом.\n\nНа iPhone нельзя вытащить из туннеля целое приложение — только сайт по адресу. В Safari обычно срабатывает. Приложение банка или маркетплейса может остаться в туннеле: у них свои адреса.\n\nКрупные сервисы сидят на куче серверов. Часть страниц или видео может идти через защиту, даже если тумблер включён. Если сайт должен быть под защитой — выключите его здесь.\n\nПосле изменения нажмите «Переподключить».';

  @override
  String get splitTunnelBundledInfoClose => 'Понятно';

  @override
  String get splitTunnelSitesLead =>
      'Сайты из списка открываются обычным интернетом, не через защиту. Остальное — через Прокси Дом.';

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
  String get splitTunnelDomainHint => 'gw.company-net.ru';

  @override
  String get splitTunnelSave => 'Добавить';

  @override
  String get splitTunnelCancel => 'Отмена';

  @override
  String get splitTunnelDelete => 'Удалить';

  @override
  String get splitTunnelDeleteConfirm => 'Удалить сайт из списка?';

  @override
  String get splitTunnelEdit => 'Редактировать';

  @override
  String get splitTunnelEditDone => 'Готово';

  @override
  String splitTunnelPlayersFound(int count) {
    return 'Плееры найдены: $count';
  }

  @override
  String splitTunnelPlayersCount(int count) {
    return 'Плееров: $count';
  }

  @override
  String get splitTunnelEmptyTitle => 'Нет своих сайтов';

  @override
  String get splitTunnelEmptyBody =>
      'Добавьте точный hostname — без туннеля пойдёт только он, не его поддомены.';

  @override
  String get splitTunnelInvalidDomain => 'Введите адрес вида gw.company-net.ru';

  @override
  String get splitTunnelDuplicateDomain => 'Этот адрес уже в списке';

  @override
  String get splitTunnelNonAsciiUnsupported => 'Только латинские адреса';

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
      'Включён Android-режим блокировки без туннеля. Приложения из этого списка могут остаться без интернета, пока вы не выключите блокировку или не вернёте их в туннель.';

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
  String get settingsLicensesHint =>
      'Лицензии движка и библиотек, с которыми он собран';

  @override
  String get licensesTitle => 'Лицензии открытого ПО';

  @override
  String get licensesSearch => 'Поиск по пакету';

  @override
  String get licensesEngine => 'Движок';

  @override
  String get licensesPackages => 'Пакеты';

  @override
  String get licensesFonts => 'Шрифты';

  @override
  String get licensesNoResults => 'Ничего не найдено';

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
  String get tunnelLogsUi => 'Интерфейс';

  @override
  String get tunnelLogsCore => 'Ядро';

  @override
  String get tunnelLogsDns => 'DNS';

  @override
  String get tunnelLogsFetch => 'Документ';

  @override
  String get tunnelLogsNetwork => 'Сеть';

  @override
  String get tunnelLogsRefresh => 'Обновить';

  @override
  String get tunnelLogsCopy => 'Копировать';

  @override
  String get tunnelLogsExport => 'Поделиться';

  @override
  String get tunnelLogsDelete => 'Удалить';

  @override
  String tunnelLogsClearBlocked(String files) {
    return 'Не удалось удалить: $files. Нужны права администратора.';
  }

  @override
  String get tunnelLogsCopied => 'Лог скопирован';

  @override
  String tunnelLogsDebugFile(String path) {
    return 'Файл для отправки: $path';
  }

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
  String get settingsReportUnauthorized =>
      'Сессия устарела — войдите снова и повторите';

  @override
  String get settingsReportNetworkError =>
      'Нет связи с сервером — попробуйте позже';

  @override
  String get settingsVpnNotificationTitle => 'Уведомление в шторке';

  @override
  String get settingsVpnNotificationShort => 'Карточка в шторке с «Отключить»';

  @override
  String get settingsVpnNotificationHint =>
      'Карточка с кнопкой «Отключить». Выключите — карточка спрячется, туннель останется.';

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
  String get settingsQsTileAddedHint => 'Нажмите, чтобы убрать';

  @override
  String get settingsQsTileRemove => 'Убрать';

  @override
  String get settingsQsTileRemoveTitle => 'Убрать плитку';

  @override
  String get settingsQsTileRemoveBody =>
      'Потяните шторку вниз, нажмите на карандаш и перетащите плитку «Прокси Дом» в корзину.';

  @override
  String get settingsQsTileRemoveAck => 'Понятно';

  @override
  String get settingsQsTileManual =>
      'Добавьте вручную: шторка → карандаш → «Прокси Дом»';

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
  String get regionSectionFree => 'Бесплатно';

  @override
  String get regionSectionEurope => 'Москва';

  @override
  String get regionSectionUsa => 'Санкт-Петербург';

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
      'API недоступен — отключите системный режим «Всегда включён» и блокировку, затем откройте список снова';

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
      'Туннельное соединение будет закрыто. В следующий раз нужно будет заново ввести код.';

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
      'На главном экране нажмите «Подключиться». Android один раз спросит разрешение на туннель — так и должно быть.';

  @override
  String get onboardingConnectBodyIos =>
      'На главном экране нажмите «Подключиться». iPhone один раз спросит разрешение на туннель — так и должно быть.';

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
      'Сервер не ответил. Если туннель включён — отключите его и повторите.';

  @override
  String get betaGateErrorUnauthorized => 'Сессия устарела. Повторите вход.';

  @override
  String get betaGateDisconnectVpnRetry => 'Отключить туннель и повторить';

  @override
  String get betaGateContinueAnyway => 'Продолжить всё равно';

  @override
  String get lockedTitle => 'Активация';

  @override
  String get lockedHeadline => 'Добро пожаловать!';

  @override
  String get lockedRefreshAccess => 'Обновить доступ';

  @override
  String get settingsSupport => 'Поддержка';

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
  String get settingsDeleteAccount => 'Удаление аккаунта';

  @override
  String get recoveryCodeTitle => 'Код восстановления';

  @override
  String get recoveryCodeHeadline => 'Код восстановления';

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
  String get settingsSeatCodeNotFound => 'Код не найден или истёк';

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
  String get vpnDisclosureTitle => 'Как включается туннель';

  @override
  String get vpnDisclosureBullet1 =>
      'Туннель включается только по вашей команде и только на этом устройстве.';

  @override
  String get vpnDisclosureBullet2 =>
      'Ключи и адреса узлов не отправляются на сервер.';

  @override
  String get vpnDisclosureBullet3 => 'Ни аккаунта, ни платежей, ни рекламы.';

  @override
  String get vpnDisclosureMore => 'Подробнее';

  @override
  String get vpnDisclosureClose => 'Закрыть';

  @override
  String get vpnDisclosureLead =>
      'Приложение включает туннель по выбранной строке. Сейчас Android один раз спросит разрешение на туннель.';

  @override
  String get vpnDisclosureVpnTitle => 'Что делает приложение';

  @override
  String get vpnDisclosureVpnBody =>
      'После согласия приложение поднимает локальный туннель для выбранной строки. Трафик идёт на сервер из этой строки. Android один раз спросит разрешение на туннель.';

  @override
  String get vpnDisclosureVpnTitleIos => 'Что делает приложение';

  @override
  String get vpnDisclosureVpnBodyIos =>
      'После согласия приложение поднимает локальный туннель для выбранной строки. Трафик идёт на сервер из этой строки. iPhone один раз спросит разрешение на туннель.';

  @override
  String get vpnDisclosureDataTitle => 'Что остаётся на телефоне';

  @override
  String get vpnDisclosureDataBody =>
      'Строка доступа хранится на устройстве. Диагностический отчёт уходит только если вы сами отправляете его из Настроек. История сайтов не записывается.';

  @override
  String get vpnDisclosureDataBodyIos =>
      'Строка доступа хранится на устройстве. Диагностический отчёт уходит только если вы сами отправляете его из Настроек. История сайтов не записывается.';

  @override
  String get vpnDisclosureNotTitle => 'Чего приложение не делает';

  @override
  String get vpnDisclosureNotBody =>
      'Не ведёт историю сайтов и не читает рекламный идентификатор. Не продаёт доступ и не выдаёт серверы: строку приносите вы.';

  @override
  String get vpnDisclosureAccept => 'Принимаю и продолжить';

  @override
  String get vpnDisclosureDecline => 'Не сейчас';

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
  String get freeTrafficLeft => 'Остаток';

  @override
  String get freeUptime => 'Время';

  @override
  String get freeNoProfile => 'Нет';

  @override
  String get freeAddTitle => 'Добавить';

  @override
  String get freeAddHint => 'Вставьте ссылку или ключ.';

  @override
  String get freeSaveConnect => 'Сохранить';

  @override
  String get freeSaveOnly => 'Только сохранить';

  @override
  String get freePreview => 'Найдено';

  @override
  String get freeServerAdded => 'Сервер добавлен';

  @override
  String freeImportCount(int recognized, int unsupported) {
    return 'Распознано $recognized, не поддержано $unsupported';
  }

  @override
  String get freeLinkInvalid => 'Ссылка не разобрана';

  @override
  String get freeSubscriptionLoadFail =>
      'Документ не загрузился. Адрес не ответил.';

  @override
  String get freeSubscriptionMissing => 'По этому адресу документа нет.';

  @override
  String get freeSubscriptionDeviceLimit =>
      'В этом документе кончились места для устройств. Освободите одно и обновите список.';

  @override
  String get freeSubscriptionClientRefused =>
      'Документ прислал заглушку вместо сервера.';

  @override
  String get freeSharePool => 'Поделиться';

  @override
  String get freeShareCopied => 'Ключ скопирован';

  @override
  String get freeShareFail => 'Не удалось создать ссылку';

  @override
  String get freeOnboardTitle => 'Список серверов';

  @override
  String get freeOnboardBody =>
      'Адрес документа или ключ становятся профилем. Узлы из него собираются в один список: Москва (Основной узел), Санкт-Петербург (Запасной), Новосибирск (Низкий пинг).';

  @override
  String get freeOnboardAddTitle => 'Выберите сервер';

  @override
  String get freeOnboardAddBody =>
      'У каждого сервера своё имя и подпись. Какой использовать — выбираете вы.';

  @override
  String get freeOnboardConnectTitle => 'Подключайтесь одним нажатием';

  @override
  String get freeOnboardConnectBody =>
      'Нажмите кнопку подключения в центре экрана. Она включает и выключает туннель. Статус остаётся на этом экране.';

  @override
  String get pcOnboardHeadline => 'Подключение на компьютере';

  @override
  String get pcOnboardBody =>
      'Вставьте ключ доступа или ссылку на документ. Приложение покажет узлы, которые в нём есть, — например, gw.company-net.ru.';

  @override
  String get pcOnboardPrivacy =>
      'Ключи и адреса серверов хранятся на этом компьютере.';

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
  String get freePoolMarked => 'Особые';

  @override
  String get freeIosHy2Only =>
      'Подключение недоступно (протокол не поддерживается клиентом).';

  @override
  String get freeHy2OnlyAdd =>
      'Не удалось добавить узел: этот протокол не запускается на этом устройстве.';

  @override
  String get freeNoHy2Lines =>
      'В источнике нет линий, которые клиент может запустить.';

  @override
  String get freeSchemeParked =>
      'Подключение недоступно (протокол не поддерживается клиентом).';

  @override
  String get freePoolGeneral => 'Общего назначения';

  @override
  String get freeSearch => 'Поиск серверов';

  @override
  String get freeSearchEmpty => 'Серверы не найдены';

  @override
  String get qrHint => 'Наведите камеру на QR-код';

  @override
  String get qrTorch => 'Фонарик';

  @override
  String get locationsNodes => 'Узлы';

  @override
  String get locationsSelected => 'ВЫБРАН';

  @override
  String get locationsActive => 'Активен';

  @override
  String get locationsNotUsed => 'НЕ ВЫБРАН';

  @override
  String get locationsUseIt => 'Подключить';

  @override
  String get locationsInUse => 'Подключено';

  @override
  String get locationsShareKey => 'Ключ';

  @override
  String get freeTelegram => 'Telegram';

  @override
  String get locationsKeyHandle => 'ключ';

  @override
  String get freeDelete => 'Удалить';

  @override
  String get freeDeleteServerTitle => 'Удалить этот сервер?';

  @override
  String get freeDeleteServerBody => 'Ссылка сотрётся с этого устройства.';

  @override
  String get freeDeleteCatalogTitle => 'Удалить этот список?';

  @override
  String get freeDeleteCatalogBody =>
      'Все серверы из списка сотрутся с этого устройства.';

  @override
  String get freeRefresh => 'Обновить';

  @override
  String freeRefreshDone(int count) {
    return 'Обновлено: $count';
  }

  @override
  String get freeRefreshFail => 'Не удалось обновить';

  @override
  String get freeStepLink => 'Ссылка';

  @override
  String get freeStepFound => 'Найдено';

  @override
  String get freeFoundEmpty =>
      'Здесь появятся узлы из ссылки — например, Москва (Основной узел) или Санкт-Петербург (Запасной).';

  @override
  String get freeFieldEmpty =>
      'Пока пусто. Вставьте ссылку — и мир увидит что внутри.';
}
