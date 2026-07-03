// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Teremok Connect';

  @override
  String get loginTitle => 'Sign in';

  @override
  String get loginPlaceholderHint => 'Phone number field comes in step 6';

  @override
  String get loginTestButton => 'Sign in (test button)';

  @override
  String get loginPhoneLabel => 'Phone number';

  @override
  String get loginPhoneHint => '+7 999 123 4567';

  @override
  String get loginPhoneHelper => 'We\'ll call you for verification';

  @override
  String get loginPhoneError => 'Format: +7XXXXXXXXXX (must be 12 chars)';

  @override
  String get loginCallButton => 'Call me';

  @override
  String get loginCallingTitle => 'Calling...';

  @override
  String get homeTitle => 'Home';

  @override
  String get homeVpnHint => 'VPN UI — comes in step 9+';

  @override
  String get homeDisconnected => 'Disconnected';

  @override
  String get homeConnecting => 'Connecting...';

  @override
  String get homeConnected => 'Connected';

  @override
  String get homeError => 'Connection failed';

  @override
  String get homeConnect => 'Connect';

  @override
  String get homeDisconnect => 'Disconnect';

  @override
  String get homeRegion => 'Region';

  @override
  String get homeSettings => 'Settings';

  @override
  String get homeAbout => 'About';

  @override
  String homeConfigError(String message) {
    return 'Failed to get config: $message';
  }

  @override
  String get homeFetchConfig => 'Fetch config';

  @override
  String get logoutTooltip => 'Sign out';

  @override
  String get verifyTitle => 'Enter code';

  @override
  String verifySentTo(String phone) {
    return 'We called $phone';
  }

  @override
  String get verifyResend => 'Resend call';

  @override
  String verifyResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get verifyWrongCode => 'Wrong code, try again';

  @override
  String get switchLanguage => 'EN';
}
