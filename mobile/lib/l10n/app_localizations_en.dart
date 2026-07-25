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
  String get homeTitle => 'Teremok';

  @override
  String get homeVpnHint => 'VPN UI — comes in step 9+';

  @override
  String get homeDisconnected => 'Disconnected';

  @override
  String get homeConnecting => 'Connecting...';

  @override
  String get homeConnected => 'Connected';

  @override
  String get homeProtected => 'Protected';

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
  String get homeStatServer => 'Server';

  @override
  String get homeStatPing => 'Ping';

  @override
  String get homeLinkOnline => 'Home online';

  @override
  String get homeLinkOffline => 'Home offline';

  @override
  String get homeLinkLabel => 'Link';

  @override
  String get homeStatDownload => 'Download';

  @override
  String get homeStatUpload => 'Upload';

  @override
  String get homeStatPlaceholder => '—';

  @override
  String get homeMoreMenu => 'More';

  @override
  String get homeRetry => 'Retry';

  @override
  String get homeErrorFriendly => 'Couldn’t connect. Please try again.';

  @override
  String get homeConfigErrorFriendly =>
      'Couldn’t fetch config. Check your connection and try again.';

  @override
  String get networkErrorFriendly =>
      'No connection to the server. Please try again.';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsSectionConnection => 'Connection';

  @override
  String get settingsSectionApp => 'Application';

  @override
  String get settingsPhone => 'Phone number';

  @override
  String get settingsPhoneReadonly =>
      'Phone changes only when you sign in again';

  @override
  String get settingsSubscription => 'Access';

  @override
  String get settingsSubscriptionActive => 'Active';

  @override
  String get settingsProBadge => 'PRO';

  @override
  String get settingsActiveBadge => 'Active';

  @override
  String get settingsAccessEarlyTitle => 'Early access';

  @override
  String get settingsAccessEarlySubtitle =>
      'Everything is open for now, no limits.';

  @override
  String settingsAccessActiveUntil(String date) {
    return 'Valid until $date.';
  }

  @override
  String get settingsAccessCancelledSubtitle => 'Auto-renewal is off.';

  @override
  String settingsSubscriptionActiveUntil(String date) {
    return 'Active until $date';
  }

  @override
  String settingsSubscriptionTrialUntil(String date) {
    return 'Trial until $date';
  }

  @override
  String get settingsSubscriptionAlpha => 'Early access';

  @override
  String get settingsSubscriptionExpired => 'Subscription expired';

  @override
  String get settingsSubscriptionLoadError => 'Couldn’t load status';

  @override
  String get settingsServerRegion => 'Server region';

  @override
  String get settingsProtocol => 'Protocol';

  @override
  String get settingsProtocolLocked =>
      'Only VLESS + Reality is available for now';

  @override
  String get settingsKillSwitch => 'Kill switch';

  @override
  String get settingsKillSwitchHint => 'Block internet if the VPN drops';

  @override
  String get settingsKillSwitchHintSystem =>
      'Enable Always-on VPN and Block connections without VPN in system VPN settings';

  @override
  String get settingsAutoReconnect => 'Auto-reconnect';

  @override
  String get settingsAutoReconnectHint =>
      'Reconnect quickly if the tunnel drops';

  @override
  String get settingsDarkTheme => 'Dark theme';

  @override
  String get settingsThemeSystem => 'Match system';

  @override
  String get settingsThemeDark => 'Always dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsDiagnostics => 'Diagnostics';

  @override
  String get settingsDiagnosticsHint => 'Check connection';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSendReport => 'Send diagnostic report';

  @override
  String get settingsSendReportHint =>
      'Sent to the owner for debugging. Your phone number is masked on the server.';

  @override
  String get settingsSendReportConfirm => 'Send';

  @override
  String get settingsReportSent => 'Report sent';

  @override
  String settingsReportFailed(String error) {
    return 'Failed to send report: $error';
  }

  @override
  String get settingsVpnNotificationTitle => 'Shade notification';

  @override
  String get settingsVpnNotificationHint =>
      'Detailed card: region, speed, disconnect';

  @override
  String get settingsQsTileTitle => 'Quick Settings tile';

  @override
  String get settingsQsTileHint =>
      'Connect and disconnect from the Android Quick Settings shade';

  @override
  String get settingsQsTileAdd => 'Add to Quick Settings';

  @override
  String get settingsQsTileAddHint => 'Show the system prompt to pin the tile';

  @override
  String get settingsQsTileAdded => 'Tile added to Quick Settings';

  @override
  String get settingsQsTileAlreadyAdded =>
      'Tile already in Quick Settings — open the shade and scroll';

  @override
  String get settingsQsTileManual =>
      'Add manually: shade → pencil → “Teremok VPN”';

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
  String get homeSessionLabel => 'Session';

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
  String get homeVpnDisconnected => 'Disconnected';

  @override
  String get homeDisconnectUndo => 'Undo';

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
  String get regionSectionOffline => 'Unavailable servers';

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

  @override
  String get updateAvailableTitle => 'Update available';

  @override
  String updateAvailableBody(String version) {
    return 'Version $version is available. Please update.';
  }

  @override
  String get updateNow => 'Update';

  @override
  String get updateLater => 'Later';
}
