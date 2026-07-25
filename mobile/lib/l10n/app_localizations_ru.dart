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
  String get homeDisconnected => 'Отключено';

  @override
  String get homeConnecting => 'Подключение...';

  @override
  String get homeConnected => 'Подключено';

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
  String get settingsAccessEarlyTitle => 'Ранний доступ';

  @override
  String get settingsAccessEarlySubtitle =>
      'Пока открыто всё, без ограничений.';

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
  String get settingsSubscriptionAlpha => 'Ранний доступ';

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
  String get settingsKillSwitch => 'Kill switch';

  @override
  String get settingsKillSwitchHint => 'Отключить интернет при разрыве VPN';

  @override
  String get settingsKillSwitchHintSystem =>
      'Включите «Всегда VPN» и «Блокировать без VPN» в системных настройках VPN';

  @override
  String get settingsAutoReconnect => 'Авто-переподключение';

  @override
  String get settingsAutoReconnectHint => 'Быстрое переподключение при обрыве';

  @override
  String get settingsDarkTheme => 'Тёмная тема';

  @override
  String get settingsThemeSystem => 'Как в системе';

  @override
  String get settingsThemeDark => 'Всегда тёмная';

  @override
  String get settingsThemeLight => 'Светлая';

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
  String settingsReportFailed(String error) {
    return 'Не удалось отправить отчёт: $error';
  }

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
}
