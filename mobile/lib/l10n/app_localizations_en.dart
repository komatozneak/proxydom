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
  String get loginPhoneError => 'Enter a valid number for the selected country';

  @override
  String get loginErrorTimeout => 'Server did not respond';

  @override
  String get loginErrorNetwork => 'No connection to server';

  @override
  String get loginErrorGeneric => 'Request failed';

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
  String homeUptime(String time) {
    return 'Session: $time';
  }

  @override
  String homeServer(String name) {
    return 'Server: $name';
  }

  @override
  String homeIp(String ip) {
    return 'Your IP: $ip';
  }

  @override
  String get homeIpLoading => 'Your IP: …';

  @override
  String get homeIpUnavailable =>
      'Your IP: unavailable — tunnel has no internet';

  @override
  String get homeIpLockdownHint =>
      'Disable Always-on “Block connections without VPN” in system VPN settings, then reconnect';

  @override
  String get homeRegionAuto => 'Auto';

  @override
  String get regionTitle => 'Region';

  @override
  String get regionSubtitle => 'Pick a server or leave automatic selection';

  @override
  String get regionAutoTitle => 'Automatic';

  @override
  String get regionAutoSubtitle => 'Best available server';

  @override
  String get regionSelected => 'Selected';

  @override
  String get regionSectionServers => 'Servers';

  @override
  String get regionOnline => 'online';

  @override
  String get regionOffline => 'offline';

  @override
  String get regionFree => 'Available';

  @override
  String get regionNoneOnline => 'No servers online — try again later';

  @override
  String regionLoadError(String error) {
    return 'Failed to load servers: $error';
  }

  @override
  String get regionLoadErrorAbort =>
      'Cannot reach API — turn off Always-on VPN (and “Block without VPN”), then reopen the region list';

  @override
  String get regionEmpty => 'No servers available';

  @override
  String regionChanged(String name) {
    return 'Region: $name';
  }

  @override
  String regionChangeFailed(String error) {
    return 'Failed to change region: $error';
  }

  @override
  String get logoutTooltip => 'Sign out';

  @override
  String get logoutConfirmTitle => 'Sign out?';

  @override
  String get logoutConfirmMessage =>
      'Your VPN connection will be closed. You\'ll need to verify again next time.';

  @override
  String get logoutWarning => 'Logout completed with warnings';

  @override
  String get cancel => 'Cancel';

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
