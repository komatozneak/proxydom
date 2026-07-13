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
  String get loginPhoneLabel => 'Номер телефона';

  @override
  String get loginPhoneHint => '+7 999 123 4567';

  @override
  String get loginPhoneHelper => 'Позвоним для подтверждения';

  @override
  String get loginPhoneError => 'Введите корректный номер для выбранной страны';

  @override
  String get loginErrorTimeout => 'Нет ответа от сервера';

  @override
  String get loginErrorNetwork => 'Нет связи с сервером';

  @override
  String get loginErrorGeneric => 'Не удалось выполнить запрос';

  @override
  String get loginCallButton => 'Позвонить';

  @override
  String get loginCallingTitle => 'Звоним...';

  @override
  String get homeTitle => 'Главная';

  @override
  String get homeVpnHint => 'VPN UI — в шагах 9+';

  @override
  String get homeDisconnected => 'Отключено';

  @override
  String get homeConnecting => 'Подключение...';

  @override
  String get homeConnected => 'Подключено';

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
  String get homeIpUnavailable => 'Ваш IP: недоступен';

  @override
  String get homeRegionAuto => 'Авто';

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
  String get verifyTitle => 'Введите код';

  @override
  String verifySentTo(String phone) {
    return 'Позвонили на $phone';
  }

  @override
  String get verifyResend => 'Перезвонить';

  @override
  String verifyResendIn(int seconds) {
    return 'Перезвонить через $secondsс';
  }

  @override
  String get verifyWrongCode => 'Неверный код, попробуйте снова';

  @override
  String get switchLanguage => 'RU';
}
