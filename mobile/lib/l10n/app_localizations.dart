import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// Title shown in app bar and OS task switcher
  ///
  /// In en, this message translates to:
  /// **'Teremok Connect'**
  String get appTitle;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginTitle;

  /// No description provided for @loginPlaceholderHint.
  ///
  /// In en, this message translates to:
  /// **'Phone number field comes in step 6'**
  String get loginPlaceholderHint;

  /// No description provided for @loginTestButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in (test button)'**
  String get loginTestButton;

  /// No description provided for @loginPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get loginPhoneLabel;

  /// No description provided for @loginPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'+7 999 123 4567'**
  String get loginPhoneHint;

  /// No description provided for @loginPhoneHelper.
  ///
  /// In en, this message translates to:
  /// **'We\'ll call you for verification'**
  String get loginPhoneHelper;

  /// No description provided for @loginPhoneError.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number for the selected country'**
  String get loginPhoneError;

  /// No description provided for @loginErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Server did not respond'**
  String get loginErrorTimeout;

  /// No description provided for @loginErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'No connection to server'**
  String get loginErrorNetwork;

  /// No description provided for @loginErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Request failed'**
  String get loginErrorGeneric;

  /// No description provided for @loginCallButton.
  ///
  /// In en, this message translates to:
  /// **'Call me'**
  String get loginCallButton;

  /// No description provided for @loginCallingTitle.
  ///
  /// In en, this message translates to:
  /// **'Calling...'**
  String get loginCallingTitle;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Teremok'**
  String get homeTitle;

  /// No description provided for @homeVpnHint.
  ///
  /// In en, this message translates to:
  /// **'VPN UI — comes in step 9+'**
  String get homeVpnHint;

  /// No description provided for @homeDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get homeDisconnected;

  /// No description provided for @homeConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get homeConnecting;

  /// No description provided for @homeConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get homeConnected;

  /// No description provided for @homeProtected.
  ///
  /// In en, this message translates to:
  /// **'Protected'**
  String get homeProtected;

  /// No description provided for @homeError.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get homeError;

  /// No description provided for @homeConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get homeConnect;

  /// No description provided for @homeDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get homeDisconnect;

  /// No description provided for @homeRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get homeRegion;

  /// No description provided for @homeSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get homeSettings;

  /// No description provided for @homeStatServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get homeStatServer;

  /// No description provided for @homeStatPing.
  ///
  /// In en, this message translates to:
  /// **'Ping'**
  String get homeStatPing;

  /// No description provided for @homeLinkOnline.
  ///
  /// In en, this message translates to:
  /// **'Home online'**
  String get homeLinkOnline;

  /// No description provided for @homeLinkOffline.
  ///
  /// In en, this message translates to:
  /// **'Home offline'**
  String get homeLinkOffline;

  /// No description provided for @homeLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get homeLinkLabel;

  /// No description provided for @homeStatDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get homeStatDownload;

  /// No description provided for @homeStatUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get homeStatUpload;

  /// No description provided for @homeStatPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get homeStatPlaceholder;

  /// No description provided for @homeMoreMenu.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get homeMoreMenu;

  /// No description provided for @homeRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get homeRetry;

  /// No description provided for @homeErrorFriendly.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t connect. Please try again.'**
  String get homeErrorFriendly;

  /// No description provided for @homeConfigErrorFriendly.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t fetch config. Check your connection and try again.'**
  String get homeConfigErrorFriendly;

  /// No description provided for @networkErrorFriendly.
  ///
  /// In en, this message translates to:
  /// **'No connection to the server. Please try again.'**
  String get networkErrorFriendly;

  /// No description provided for @settingsSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// No description provided for @settingsSectionConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsSectionConnection;

  /// No description provided for @settingsSectionApp.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get settingsSectionApp;

  /// No description provided for @settingsPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get settingsPhone;

  /// No description provided for @settingsPhoneReadonly.
  ///
  /// In en, this message translates to:
  /// **'Phone changes only when you sign in again'**
  String get settingsPhoneReadonly;

  /// No description provided for @settingsSubscription.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get settingsSubscription;

  /// No description provided for @settingsSubscriptionActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get settingsSubscriptionActive;

  /// No description provided for @settingsProBadge.
  ///
  /// In en, this message translates to:
  /// **'PRO'**
  String get settingsProBadge;

  /// No description provided for @settingsActiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get settingsActiveBadge;

  /// No description provided for @settingsAccessEarlyTitle.
  ///
  /// In en, this message translates to:
  /// **'Early access'**
  String get settingsAccessEarlyTitle;

  /// No description provided for @settingsAccessEarlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Everything is open for now, no limits.'**
  String get settingsAccessEarlySubtitle;

  /// No description provided for @settingsAccessActiveUntil.
  ///
  /// In en, this message translates to:
  /// **'Valid until {date}.'**
  String settingsAccessActiveUntil(String date);

  /// No description provided for @settingsAccessCancelledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-renewal is off.'**
  String get settingsAccessCancelledSubtitle;

  /// No description provided for @settingsSubscriptionActiveUntil.
  ///
  /// In en, this message translates to:
  /// **'Active until {date}'**
  String settingsSubscriptionActiveUntil(String date);

  /// No description provided for @settingsSubscriptionTrialUntil.
  ///
  /// In en, this message translates to:
  /// **'Trial until {date}'**
  String settingsSubscriptionTrialUntil(String date);

  /// No description provided for @settingsSubscriptionAlpha.
  ///
  /// In en, this message translates to:
  /// **'Early access'**
  String get settingsSubscriptionAlpha;

  /// No description provided for @settingsSubscriptionExpired.
  ///
  /// In en, this message translates to:
  /// **'Subscription expired'**
  String get settingsSubscriptionExpired;

  /// No description provided for @settingsSubscriptionLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load status'**
  String get settingsSubscriptionLoadError;

  /// No description provided for @settingsServerRegion.
  ///
  /// In en, this message translates to:
  /// **'Server region'**
  String get settingsServerRegion;

  /// No description provided for @settingsProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get settingsProtocol;

  /// No description provided for @settingsProtocolLocked.
  ///
  /// In en, this message translates to:
  /// **'Only VLESS + Reality is available for now'**
  String get settingsProtocolLocked;

  /// No description provided for @settingsKillSwitch.
  ///
  /// In en, this message translates to:
  /// **'Kill switch'**
  String get settingsKillSwitch;

  /// No description provided for @settingsKillSwitchHint.
  ///
  /// In en, this message translates to:
  /// **'Block internet if the VPN drops'**
  String get settingsKillSwitchHint;

  /// No description provided for @settingsKillSwitchHintSystem.
  ///
  /// In en, this message translates to:
  /// **'Enable Always-on VPN and Block connections without VPN in system VPN settings'**
  String get settingsKillSwitchHintSystem;

  /// No description provided for @settingsAutoReconnect.
  ///
  /// In en, this message translates to:
  /// **'Auto-reconnect'**
  String get settingsAutoReconnect;

  /// No description provided for @settingsAutoReconnectHint.
  ///
  /// In en, this message translates to:
  /// **'Reconnect quickly if the tunnel drops'**
  String get settingsAutoReconnectHint;

  /// No description provided for @settingsDarkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark theme'**
  String get settingsDarkTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'Match system'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Always dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settingsDiagnostics;

  /// No description provided for @settingsDiagnosticsHint.
  ///
  /// In en, this message translates to:
  /// **'Check connection'**
  String get settingsDiagnosticsHint;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSendReport.
  ///
  /// In en, this message translates to:
  /// **'Send diagnostic report'**
  String get settingsSendReport;

  /// No description provided for @settingsSendReportHint.
  ///
  /// In en, this message translates to:
  /// **'Sent to the owner for debugging. Your phone number is masked on the server.'**
  String get settingsSendReportHint;

  /// No description provided for @settingsSendReportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get settingsSendReportConfirm;

  /// No description provided for @settingsReportSent.
  ///
  /// In en, this message translates to:
  /// **'Report sent'**
  String get settingsReportSent;

  /// No description provided for @settingsReportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send report: {error}'**
  String settingsReportFailed(String error);

  /// No description provided for @settingsVpnNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Shade notification'**
  String get settingsVpnNotificationTitle;

  /// No description provided for @settingsVpnNotificationHint.
  ///
  /// In en, this message translates to:
  /// **'Detailed card: region, speed, disconnect'**
  String get settingsVpnNotificationHint;

  /// No description provided for @settingsQsTileTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Settings tile'**
  String get settingsQsTileTitle;

  /// No description provided for @settingsQsTileHint.
  ///
  /// In en, this message translates to:
  /// **'Connect and disconnect from the Android Quick Settings shade'**
  String get settingsQsTileHint;

  /// No description provided for @settingsQsTileAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to Quick Settings'**
  String get settingsQsTileAdd;

  /// No description provided for @settingsQsTileAddHint.
  ///
  /// In en, this message translates to:
  /// **'Show the system prompt to pin the tile'**
  String get settingsQsTileAddHint;

  /// No description provided for @settingsQsTileAdded.
  ///
  /// In en, this message translates to:
  /// **'Tile added to Quick Settings'**
  String get settingsQsTileAdded;

  /// No description provided for @settingsQsTileAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'Tile already in Quick Settings — open the shade and scroll'**
  String get settingsQsTileAlreadyAdded;

  /// No description provided for @settingsQsTileManual.
  ///
  /// In en, this message translates to:
  /// **'Add manually: shade → pencil → “Teremok VPN”'**
  String get settingsQsTileManual;

  /// No description provided for @homeAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get homeAbout;

  /// No description provided for @homeConfigError.
  ///
  /// In en, this message translates to:
  /// **'Failed to get config: {message}'**
  String homeConfigError(String message);

  /// No description provided for @homeFetchConfig.
  ///
  /// In en, this message translates to:
  /// **'Fetch config'**
  String get homeFetchConfig;

  /// No description provided for @homeUptime.
  ///
  /// In en, this message translates to:
  /// **'Session: {time}'**
  String homeUptime(String time);

  /// No description provided for @homeSessionLabel.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get homeSessionLabel;

  /// No description provided for @homeServer.
  ///
  /// In en, this message translates to:
  /// **'Server: {name}'**
  String homeServer(String name);

  /// No description provided for @homeIp.
  ///
  /// In en, this message translates to:
  /// **'Your IP: {ip}'**
  String homeIp(String ip);

  /// No description provided for @homeIpLoading.
  ///
  /// In en, this message translates to:
  /// **'Your IP: …'**
  String get homeIpLoading;

  /// No description provided for @homeIpUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Your IP: unavailable — tunnel has no internet'**
  String get homeIpUnavailable;

  /// No description provided for @homeIpLockdownHint.
  ///
  /// In en, this message translates to:
  /// **'Disable Always-on “Block connections without VPN” in system VPN settings, then reconnect'**
  String get homeIpLockdownHint;

  /// No description provided for @homeRegionAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get homeRegionAuto;

  /// No description provided for @homeVpnDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get homeVpnDisconnected;

  /// No description provided for @homeDisconnectUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get homeDisconnectUndo;

  /// No description provided for @regionTitle.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get regionTitle;

  /// No description provided for @regionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a server or leave automatic selection'**
  String get regionSubtitle;

  /// No description provided for @regionAutoTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get regionAutoTitle;

  /// No description provided for @regionAutoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Best available server'**
  String get regionAutoSubtitle;

  /// No description provided for @regionSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get regionSelected;

  /// No description provided for @regionSectionServers.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get regionSectionServers;

  /// No description provided for @regionSectionOffline.
  ///
  /// In en, this message translates to:
  /// **'Unavailable servers'**
  String get regionSectionOffline;

  /// No description provided for @regionOnline.
  ///
  /// In en, this message translates to:
  /// **'online'**
  String get regionOnline;

  /// No description provided for @regionOffline.
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get regionOffline;

  /// No description provided for @regionFree.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get regionFree;

  /// No description provided for @regionNoneOnline.
  ///
  /// In en, this message translates to:
  /// **'No servers online — try again later'**
  String get regionNoneOnline;

  /// No description provided for @regionLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load servers: {error}'**
  String regionLoadError(String error);

  /// No description provided for @regionLoadErrorAbort.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach API — turn off Always-on VPN (and “Block without VPN”), then reopen the region list'**
  String get regionLoadErrorAbort;

  /// No description provided for @regionEmpty.
  ///
  /// In en, this message translates to:
  /// **'No servers available'**
  String get regionEmpty;

  /// No description provided for @regionChanged.
  ///
  /// In en, this message translates to:
  /// **'Region: {name}'**
  String regionChanged(String name);

  /// No description provided for @regionChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to change region: {error}'**
  String regionChangeFailed(String error);

  /// No description provided for @logoutTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get logoutTooltip;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Your VPN connection will be closed. You\'ll need to verify again next time.'**
  String get logoutConfirmMessage;

  /// No description provided for @logoutWarning.
  ///
  /// In en, this message translates to:
  /// **'Logout completed with warnings'**
  String get logoutWarning;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @verifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter code'**
  String get verifyTitle;

  /// No description provided for @verifySentTo.
  ///
  /// In en, this message translates to:
  /// **'We called {phone}'**
  String verifySentTo(String phone);

  /// No description provided for @verifyResend.
  ///
  /// In en, this message translates to:
  /// **'Resend call'**
  String get verifyResend;

  /// No description provided for @verifyResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String verifyResendIn(int seconds);

  /// No description provided for @verifyWrongCode.
  ///
  /// In en, this message translates to:
  /// **'Wrong code, try again'**
  String get verifyWrongCode;

  /// Short label of language toggle button (shows next-language code)
  ///
  /// In en, this message translates to:
  /// **'EN'**
  String get switchLanguage;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateAvailableTitle;

  /// No description provided for @updateAvailableBody.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available. Please update.'**
  String updateAvailableBody(String version);

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateNow;

  /// No description provided for @updateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'ru':
      return AppL10nRu();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
