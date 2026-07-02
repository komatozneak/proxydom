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
  String get homeTitle => 'Главная';

  @override
  String get homeVpnHint => 'VPN UI — в шагах 9+';

  @override
  String get logoutTooltip => 'Выйти';

  @override
  String get switchLanguage => 'RU';
}
