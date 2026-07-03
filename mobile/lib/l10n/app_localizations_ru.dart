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
  String get loginPhoneError => 'Формат: +7XXXXXXXXXX (12 символов)';

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
  String get logoutTooltip => 'Выйти';

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
