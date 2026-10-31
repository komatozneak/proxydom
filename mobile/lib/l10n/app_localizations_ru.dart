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
  String get homeDisconnected => 'Не подключено';

  @override
  String get homeConnecting => 'Подключение...';

  @override
  String get homeConnected => 'Подключено';

  @override
  String get homeError => 'Ошибка подключения';

  @override
  String get homeConnect => 'Подключиться';

  @override
  String get homeRegion => 'Регион';

  @override
  String get navHome => 'Главная';

  @override
  String get navVpn => 'Подключение';

  @override
  String get homeTrafficExhausted => 'Трафик закончился';

  @override
  String get homeTrafficLabel => 'ТРАФИК';

  @override
  String get homeAddServer => 'Добавить сервер';

  @override
  String get homeMetricTime => 'Время';

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
  String get homeNoVpnRow => 'Маршрутизация';

  @override
  String get settingsNoVpn => 'Маршрутизация';

  @override
  String get settingsNoVpnHint =>
      'Правила раздельного туннеля для приложений и сайтов';

  @override
  String get navSettings => 'Настройки';

  @override
  String get homeStatServer => 'Сервер';

  @override
  String get homeStatPing => 'Пинг';

  @override
  String get homeStatPingPending => 'измеряем';

  @override
  String get homeErrorFriendly => 'Не удалось подключиться. Попробуйте снова.';

  @override
  String get homeNodeAuthRefused =>
      'Узел отклонил аутентификацию. Сессия не разрешена: трафик периода закончился или ключ отозван.';

  @override
  String get homePathIncompatibleHint =>
      'Не вышло проверить сервер. Нажмите ещё раз или выберите локацию вручную.';

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
  String get settingsSectionConnection => 'Подключение';

  @override
  String get settingsSectionApp => 'Приложение';

  @override
  String get settingsKillSwitchOpenVpn => 'Открыть настройки туннеля';

  @override
  String get settingsKillSwitchOpenFailed =>
      'Не удалось открыть настройки туннеля. Откройте Настройки → Сеть и интернет → VPN.';

  @override
  String get settingsKillSwitchOpenFailedIos =>
      'Не удалось открыть настройки туннеля. Откройте Настройки → VPN.';

  @override
  String get splitTunnelSitesLead =>
      'Сайты из списка открываются обычным интернетом, не через защиту. Остальное — через Прокси Дом.';

  @override
  String get splitTunnelCustomSection => 'Мои сайты';

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
  String get splitTunnelEmptyBody =>
      'Добавьте точный hostname — без туннеля пойдёт только он, не его поддомены.';

  @override
  String get splitTunnelInvalidDomain => 'Введите адрес вида gw.company-net.ru';

  @override
  String get splitTunnelDuplicateDomain => 'Этот адрес уже в списке';

  @override
  String get splitTunnelNonAsciiUnsupported => 'Только латинские адреса';

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
  String get settingsLanguage => 'Язык';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsPrivacyPlaceholder => 'Политика конфиденциальности';

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
  String settingsVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get settingsTitle => 'Настройки';

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
  String get settingsQsTileAdded => 'Плитка добавлена в шторку';

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
  String get homeSessionLabel => 'Сессия';

  @override
  String get regionAutoTitle => 'Автоматически';

  @override
  String get regionAutoSubtitle => 'Ближайшая локация';

  @override
  String get cancel => 'Отмена';

  @override
  String get navBack => 'Назад';

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
  String get onboardingSkip => 'Пропустить';

  @override
  String get onboardingNext => 'Далее';

  @override
  String get onboardingConnectBody =>
      'На главном экране нажмите «Подключиться». Android один раз спросит разрешение на туннель — так и должно быть.';

  @override
  String get onboardingConnectBodyIos =>
      'На главном экране нажмите «Подключиться». iPhone один раз спросит разрешение на туннель — так и должно быть.';

  @override
  String get settingsSupport => 'Поддержка';

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
  String get freeHy2OnlyAdd =>
      'Не удалось добавить узел: этот протокол не запускается на этом устройстве.';

  @override
  String get freeNoHy2Lines =>
      'В источнике нет линий, которые клиент может запустить.';

  @override
  String get freeSchemeParked =>
      'Подключение недоступно (протокол не поддерживается клиентом).';

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
  String get locationsActive => 'Активен';

  @override
  String get locationsShareKey => 'Ключ';

  @override
  String get freeTelegram => 'Telegram';

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
