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
    Locale('ru')
  ];

  /// Title shown in app bar and OS task switcher
  ///
  /// In en, this message translates to:
  /// **'Proxy Dom'**
  String get appTitle;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginTitle;

  /// No description provided for @loginTestButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in (test button)'**
  String get loginTestButton;

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

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy Dom'**
  String get homeTitle;

  /// No description provided for @homeVpnHint.
  ///
  /// In en, this message translates to:
  /// **'VPN UI — comes in step 9+'**
  String get homeVpnHint;

  /// No description provided for @homeDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
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

  /// No description provided for @homeTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the house to connect'**
  String get homeTapHint;

  /// No description provided for @homeConnectingHint.
  ///
  /// In en, this message translates to:
  /// **'Hold on — the house is opening the door…'**
  String get homeConnectingHint;

  /// No description provided for @homeConnectedHint.
  ///
  /// In en, this message translates to:
  /// **'The house is online'**
  String get homeConnectedHint;

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

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navVpn.
  ///
  /// In en, this message translates to:
  /// **'Tunnel'**
  String get navVpn;

  /// No description provided for @navLocations.
  ///
  /// In en, this message translates to:
  /// **'Locations'**
  String get navLocations;

  /// No description provided for @navModes.
  ///
  /// In en, this message translates to:
  /// **'Modes'**
  String get navModes;

  /// No description provided for @homeTrafficRemainder.
  ///
  /// In en, this message translates to:
  /// **'Data left'**
  String get homeTrafficRemainder;

  /// No description provided for @homeTrafficExhausted.
  ///
  /// In en, this message translates to:
  /// **'Traffic used up'**
  String get homeTrafficExhausted;

  /// No description provided for @homeTrafficLabel.
  ///
  /// In en, this message translates to:
  /// **'TRAFFIC'**
  String get homeTrafficLabel;

  /// No description provided for @homeTrafficUnlimited.
  ///
  /// In en, this message translates to:
  /// **'UNLIMITED'**
  String get homeTrafficUnlimited;

  /// No description provided for @homeTrafficAmount.
  ///
  /// In en, this message translates to:
  /// **'{remaining} / {limit} GB'**
  String homeTrafficAmount(String remaining, String limit);

  /// No description provided for @homeNoVpnRow.
  ///
  /// In en, this message translates to:
  /// **'Allowlists'**
  String get homeNoVpnRow;

  /// No description provided for @settingsNoVpn.
  ///
  /// In en, this message translates to:
  /// **'Allowlists'**
  String get settingsNoVpn;

  /// No description provided for @settingsNoVpnHint.
  ///
  /// In en, this message translates to:
  /// **'Apps and sites that go around'**
  String get settingsNoVpnHint;

  /// No description provided for @modesTitle.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get modesTitle;

  /// No description provided for @modesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How VPN works'**
  String get modesSubtitle;

  /// No description provided for @modeSmartTitle.
  ///
  /// In en, this message translates to:
  /// **'Smart mode'**
  String get modeSmartTitle;

  /// No description provided for @modeSmartBody.
  ///
  /// In en, this message translates to:
  /// **'Russian sites — direct, foreign sites — through VPN.'**
  String get modeSmartBody;

  /// No description provided for @modeSmartBadge.
  ///
  /// In en, this message translates to:
  /// **'AUTO'**
  String get modeSmartBadge;

  /// No description provided for @modeFullTitle.
  ///
  /// In en, this message translates to:
  /// **'Full VPN'**
  String get modeFullTitle;

  /// No description provided for @modeFullBody.
  ///
  /// In en, this message translates to:
  /// **'All traffic goes through VPN. Simple and reliable.'**
  String get modeFullBody;

  /// No description provided for @modeSitesTitle.
  ///
  /// In en, this message translates to:
  /// **'By site'**
  String get modeSitesTitle;

  /// No description provided for @modeSitesBody.
  ///
  /// In en, this message translates to:
  /// **'Only selected sites go through VPN. Everything else is direct.'**
  String get modeSitesBody;

  /// No description provided for @modesVpnOffTitle.
  ///
  /// In en, this message translates to:
  /// **'VPN is off'**
  String get modesVpnOffTitle;

  /// No description provided for @modesVpnOffBody.
  ///
  /// In en, this message translates to:
  /// **'Connect VPN so modes can take effect'**
  String get modesVpnOffBody;

  /// No description provided for @modesConfirmFullTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to Full VPN mode?'**
  String get modesConfirmFullTitle;

  /// No description provided for @modesConfirmFullBody.
  ///
  /// In en, this message translates to:
  /// **'In this mode all traffic goes through VPN. Russian services — Ozon, Wildberries, banks, Gosuslugi… may stop opening.\n\nTo keep them direct — use Smart mode.'**
  String get modesConfirmFullBody;

  /// No description provided for @modesConfirmFullCancel.
  ///
  /// In en, this message translates to:
  /// **'Don\'t switch'**
  String get modesConfirmFullCancel;

  /// No description provided for @modesConfirmFullOk.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get modesConfirmFullOk;

  /// No description provided for @modesSitesSectionSmart.
  ///
  /// In en, this message translates to:
  /// **'Also direct'**
  String get modesSitesSectionSmart;

  /// No description provided for @modesSitesSectionSites.
  ///
  /// In en, this message translates to:
  /// **'Sites through VPN'**
  String get modesSitesSectionSites;

  /// No description provided for @modesSitesCustomSection.
  ///
  /// In en, this message translates to:
  /// **'Your sites'**
  String get modesSitesCustomSection;

  /// No description provided for @modesSitesCustomHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. twitch.tv'**
  String get modesSitesCustomHint;

  /// No description provided for @modesSitesAllowlistHint.
  ///
  /// In en, this message translates to:
  /// **'Only selected sites go through VPN — everything else goes direct at full speed.'**
  String get modesSitesAllowlistHint;

  /// No description provided for @modesSitesMetaNote.
  ///
  /// In en, this message translates to:
  /// **'Instagram and Facebook belong to Meta, recognized in Russia as an extremist organization and banned in the Russian Federation.'**
  String get modesSitesMetaNote;

  /// No description provided for @modesLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get modesLocationTitle;

  /// No description provided for @modesLocationHint.
  ///
  /// In en, this message translates to:
  /// **'Server and country'**
  String get modesLocationHint;

  /// No description provided for @modesPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reconnect VPN required'**
  String get modesPendingTitle;

  /// No description provided for @modesPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Routing changes apply after you reconnect.'**
  String get modesPendingBody;

  /// No description provided for @modesReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get modesReconnect;

  /// No description provided for @modesReconnectingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting VPN…'**
  String get modesReconnectingTitle;

  /// No description provided for @modesReconnectingBody.
  ///
  /// In en, this message translates to:
  /// **'Applying routing changes'**
  String get modesReconnectingBody;

  /// No description provided for @modesReconnectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get modesReconnectedTitle;

  /// No description provided for @modesReconnectFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Reconnect failed'**
  String get modesReconnectFailedTitle;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

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

  /// No description provided for @homeNodeAuthRefused.
  ///
  /// In en, this message translates to:
  /// **'The node refused authentication. The session is not allowed: this period’s traffic is used up, or the key was revoked.'**
  String get homeNodeAuthRefused;

  /// No description provided for @homePathIncompatibleHint.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach a server. Tap again or pick a location yourself.'**
  String get homePathIncompatibleHint;

  /// No description provided for @homeTtProvisionFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Server unavailable'**
  String get homeTtProvisionFailedTitle;

  /// No description provided for @homeTtProvisionFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t prepare this location. Try again later or pick another.'**
  String get homeTtProvisionFailedHint;

  /// No description provided for @homeVpnProbeFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Server not responding'**
  String get homeVpnProbeFailedTitle;

  /// No description provided for @homeVpnProbeFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Location {node} is temporarily unavailable. Pick another in Locations or try again later.'**
  String homeVpnProbeFailedHint(String node);

  /// No description provided for @homeVpnConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Another VPN is blocking'**
  String get homeVpnConflictTitle;

  /// No description provided for @homeVpnConflictHint.
  ///
  /// In en, this message translates to:
  /// **'Turn off the other VPN in Android settings, then connect again.'**
  String get homeVpnConflictHint;

  /// No description provided for @homeVpnConflictHintIos.
  ///
  /// In en, this message translates to:
  /// **'Turn off the other VPN in Settings → VPN.'**
  String get homeVpnConflictHintIos;

  /// No description provided for @homeVpnConflictHintNamed.
  ///
  /// In en, this message translates to:
  /// **'Turn off “{app}” in Android settings, then connect again.'**
  String homeVpnConflictHintNamed(String app);

  /// No description provided for @homeVpnConflictHintNamedIos.
  ///
  /// In en, this message translates to:
  /// **'Turn off “{app}” in Settings → VPN.'**
  String homeVpnConflictHintNamedIos(String app);

  /// No description provided for @homeVpnPermissionHint.
  ///
  /// In en, this message translates to:
  /// **'Allow the VPN in the Android system prompt, then tap connect again.'**
  String get homeVpnPermissionHint;

  /// No description provided for @homeVpnPermissionHintIos.
  ///
  /// In en, this message translates to:
  /// **'Allow VPN in the system prompt, then connect again.'**
  String get homeVpnPermissionHintIos;

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

  /// No description provided for @settingsAccessEarlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Access is by invite.'**
  String get settingsAccessEarlySubtitle;

  /// No description provided for @settingsAccessBetaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Invite access · Free limits lifted.'**
  String get settingsAccessBetaSubtitle;

  /// No description provided for @settingsAccessNoneTitle.
  ///
  /// In en, this message translates to:
  /// **'No access'**
  String get settingsAccessNoneTitle;

  /// No description provided for @settingsAccessNoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'An invite code is required.'**
  String get settingsAccessNoneSubtitle;

  /// No description provided for @settingsAccessFreeTitle.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get settingsAccessFreeTitle;

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

  /// No description provided for @settingsKillSwitchOpenVpn.
  ///
  /// In en, this message translates to:
  /// **'Open VPN settings'**
  String get settingsKillSwitchOpenVpn;

  /// No description provided for @settingsKillSwitchOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open VPN settings. Open Settings → Network & internet → VPN.'**
  String get settingsKillSwitchOpenFailed;

  /// No description provided for @settingsKillSwitchOpenFailedIos.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open VPN settings. Open Settings → VPN.'**
  String get settingsKillSwitchOpenFailedIos;

  /// No description provided for @settingsDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get settingsDevices;

  /// No description provided for @settingsDevicesHint.
  ///
  /// In en, this message translates to:
  /// **'Registered installs and revoke access'**
  String get settingsDevicesHint;

  /// No description provided for @devicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devicesTitle;

  /// No description provided for @devicesHint.
  ///
  /// In en, this message translates to:
  /// **'You can log out other devices if you no longer have them.'**
  String get devicesHint;

  /// No description provided for @devicesCreated.
  ///
  /// In en, this message translates to:
  /// **'Created: {date}'**
  String devicesCreated(String date);

  /// No description provided for @devicesCurrentDevice.
  ///
  /// In en, this message translates to:
  /// **'Current device'**
  String get devicesCurrentDevice;

  /// No description provided for @devicesSectionThis.
  ///
  /// In en, this message translates to:
  /// **'This install'**
  String get devicesSectionThis;

  /// No description provided for @devicesSectionGroup.
  ///
  /// In en, this message translates to:
  /// **'In the group'**
  String get devicesSectionGroup;

  /// No description provided for @devicesSectionActions.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get devicesSectionActions;

  /// No description provided for @devicesInGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'In the group'**
  String get devicesInGroupLabel;

  /// No description provided for @devicesGroupEmpty.
  ///
  /// In en, this message translates to:
  /// **'One device so far · {count} slots left'**
  String devicesGroupEmpty(int count);

  /// No description provided for @devicesLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Device limit reached'**
  String get devicesLimitReached;

  /// No description provided for @devicesCount.
  ///
  /// In en, this message translates to:
  /// **'{active} of {max}'**
  String devicesCount(int active, int max);

  /// No description provided for @devicesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No devices yet — connect VPN to register this one.'**
  String get devicesEmpty;

  /// No description provided for @devicesLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load devices'**
  String get devicesLoadError;

  /// No description provided for @devicesUntitled.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get devicesUntitled;

  /// No description provided for @devicesRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get devicesRename;

  /// No description provided for @devicesRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get devicesRenameTitle;

  /// No description provided for @devicesRenameHint.
  ///
  /// In en, this message translates to:
  /// **'Shown in the device list'**
  String get devicesRenameHint;

  /// No description provided for @devicesRenameSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get devicesRenameSave;

  /// No description provided for @devicesRenamed.
  ///
  /// In en, this message translates to:
  /// **'Name updated'**
  String get devicesRenamed;

  /// No description provided for @devicesRenameFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not rename device'**
  String get devicesRenameFailed;

  /// No description provided for @devicesThisDevice.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get devicesThisDevice;

  /// No description provided for @devicesInvitedLabel.
  ///
  /// In en, this message translates to:
  /// **'Invited device'**
  String get devicesInvitedLabel;

  /// No description provided for @devicesRevoke.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get devicesRevoke;

  /// No description provided for @devicesRevokeTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke this device?'**
  String get devicesRevokeTitle;

  /// No description provided for @devicesRevokeBody.
  ///
  /// In en, this message translates to:
  /// **'This device\'s VPN key will stop working. Other devices are unaffected.'**
  String get devicesRevokeBody;

  /// No description provided for @devicesRevokeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get devicesRevokeConfirm;

  /// No description provided for @devicesCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get devicesCancel;

  /// No description provided for @devicesRevoked.
  ///
  /// In en, this message translates to:
  /// **'Device revoked'**
  String get devicesRevoked;

  /// No description provided for @devicesRevokeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not revoke device'**
  String get devicesRevokeFailed;

  /// No description provided for @devicesLeaveHint.
  ///
  /// In en, this message translates to:
  /// **'This install becomes its own Free account'**
  String get devicesLeaveHint;

  /// No description provided for @devicesLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get devicesLeaveConfirm;

  /// No description provided for @devicesLeft.
  ///
  /// In en, this message translates to:
  /// **'Device left the account'**
  String get devicesLeft;

  /// No description provided for @devicesLeaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not leave the account'**
  String get devicesLeaveFailed;

  /// No description provided for @devicesLogoutAll.
  ///
  /// In en, this message translates to:
  /// **'Sign out everywhere'**
  String get devicesLogoutAll;

  /// No description provided for @devicesLogoutAllHint.
  ///
  /// In en, this message translates to:
  /// **'Revoke every device on this account, including this one'**
  String get devicesLogoutAllHint;

  /// No description provided for @devicesLogoutAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out on all devices?'**
  String get devicesLogoutAllTitle;

  /// No description provided for @devicesLogoutAllBody.
  ///
  /// In en, this message translates to:
  /// **'Every device on this account will lose access, including this one. Recover with your code or register again.'**
  String get devicesLogoutAllBody;

  /// No description provided for @devicesLogoutAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out everywhere'**
  String get devicesLogoutAllConfirm;

  /// No description provided for @devicesLogoutAllFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not sign out everywhere'**
  String get devicesLogoutAllFailed;

  /// No description provided for @devicesLimitOpenManage.
  ///
  /// In en, this message translates to:
  /// **'Manage devices'**
  String get devicesLimitOpenManage;

  /// No description provided for @splitTunnelSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search my sites'**
  String get splitTunnelSearchHint;

  /// No description provided for @splitTunnelBundledSection.
  ///
  /// In en, this message translates to:
  /// **'Ready-made list'**
  String get splitTunnelBundledSection;

  /// No description provided for @splitTunnelBundledLead.
  ///
  /// In en, this message translates to:
  /// **'Listed sites use your usual connection, not the protected one. Everything else still goes through Proxy Dom.'**
  String get splitTunnelBundledLead;

  /// No description provided for @splitTunnelBundledRuTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready-made lists'**
  String get splitTunnelBundledRuTitle;

  /// No description provided for @splitTunnelBundledRuSubtitle.
  ///
  /// In en, this message translates to:
  /// **'VK, Yandex, marketplaces, MAX, and more — one tap'**
  String get splitTunnelBundledRuSubtitle;

  /// No description provided for @splitTunnelBundledInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get splitTunnelBundledInfoTitle;

  /// No description provided for @splitTunnelBundledInfoBody.
  ///
  /// In en, this message translates to:
  /// **'Listed sites use your usual connection, not the protected one. Everything else still goes through Proxy Dom.\n\nOn iPhone you cannot take a whole app out of the VPN — only a website by address. Safari usually follows the list. A bank or marketplace app may stay in the VPN.\n\nBig services use many servers. Some pages or video may still go through the VPN with the switch on. If a site should stay protected, turn it off here.\n\nTap Reconnect after you change the list.'**
  String get splitTunnelBundledInfoBody;

  /// No description provided for @splitTunnelBundledInfoClose.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get splitTunnelBundledInfoClose;

  /// No description provided for @splitTunnelSitesLead.
  ///
  /// In en, this message translates to:
  /// **'Listed sites use your usual connection, not the protected one. Everything else still goes through Proxy Dom.'**
  String get splitTunnelSitesLead;

  /// No description provided for @splitTunnelSitesIosNote.
  ///
  /// In en, this message translates to:
  /// **'On iPhone only exact hostnames leave the VPN (not all subdomains). Whole apps cannot leave the tunnel.'**
  String get splitTunnelSitesIosNote;

  /// No description provided for @splitTunnelCustomSection.
  ///
  /// In en, this message translates to:
  /// **'My sites'**
  String get splitTunnelCustomSection;

  /// No description provided for @splitTunnelCustomCount.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String splitTunnelCustomCount(int count);

  /// No description provided for @splitTunnelAddSite.
  ///
  /// In en, this message translates to:
  /// **'Add site'**
  String get splitTunnelAddSite;

  /// No description provided for @splitTunnelSiteNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get splitTunnelSiteNameOptional;

  /// No description provided for @splitTunnelDomainLabel.
  ///
  /// In en, this message translates to:
  /// **'Site address'**
  String get splitTunnelDomainLabel;

  /// No description provided for @splitTunnelDomainHint.
  ///
  /// In en, this message translates to:
  /// **'example.com'**
  String get splitTunnelDomainHint;

  /// No description provided for @splitTunnelSave.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get splitTunnelSave;

  /// No description provided for @splitTunnelCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get splitTunnelCancel;

  /// No description provided for @splitTunnelDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get splitTunnelDelete;

  /// No description provided for @splitTunnelDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this site from the list?'**
  String get splitTunnelDeleteConfirm;

  /// No description provided for @splitTunnelEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No custom sites'**
  String get splitTunnelEmptyTitle;

  /// No description provided for @splitTunnelEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add an exact hostname — only that address skips the VPN, not its subdomains.'**
  String get splitTunnelEmptyBody;

  /// No description provided for @splitTunnelInvalidDomain.
  ///
  /// In en, this message translates to:
  /// **'Enter an address like example.com'**
  String get splitTunnelInvalidDomain;

  /// No description provided for @splitTunnelDuplicateDomain.
  ///
  /// In en, this message translates to:
  /// **'This address is already in the list'**
  String get splitTunnelDuplicateDomain;

  /// No description provided for @splitTunnelNonAsciiUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Latin addresses only'**
  String get splitTunnelNonAsciiUnsupported;

  /// No description provided for @splitTunnelDomainLatinHelper.
  ///
  /// In en, this message translates to:
  /// **'Latin addresses only'**
  String get splitTunnelDomainLatinHelper;

  /// No description provided for @splitTunnelPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Changes not applied yet'**
  String get splitTunnelPendingTitle;

  /// No description provided for @splitTunnelPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Changes apply after reconnecting'**
  String get splitTunnelPendingBody;

  /// No description provided for @splitTunnelReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get splitTunnelReconnect;

  /// No description provided for @splitTunnelReconnectInProgress.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get splitTunnelReconnectInProgress;

  /// No description provided for @splitTunnelApplied.
  ///
  /// In en, this message translates to:
  /// **'Rules applied'**
  String get splitTunnelApplied;

  /// No description provided for @splitTunnelApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reconnect — try again'**
  String get splitTunnelApplyFailed;

  /// No description provided for @splitTunnelAppsLockdownWarning.
  ///
  /// In en, this message translates to:
  /// **'Android “Block connections without VPN” is on. Apps in this list may have no internet until you turn that off or reconnect them through the VPN.'**
  String get splitTunnelAppsLockdownWarning;

  /// No description provided for @splitTunnelGeoHy2Pending.
  ///
  /// In en, this message translates to:
  /// **'Not applied on this connection yet (needs IP lists). Use Apps or add a site.'**
  String get splitTunnelGeoHy2Pending;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Native name for Russian — keep Cyrillic in all locales
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get settingsLanguageRussian;

  /// Native name for English — keep Latin in all locales
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon — placeholder for now'**
  String get settingsComingSoon;

  /// No description provided for @settingsComingSoonBadge.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get settingsComingSoonBadge;

  /// No description provided for @settingsPrivacyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get settingsPrivacyPlaceholder;

  /// No description provided for @settingsDarkTheme.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsDarkTheme;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsLicensesHint.
  ///
  /// In en, this message translates to:
  /// **'Licenses of the engine and the libraries it links'**
  String get settingsLicensesHint;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
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

  /// No description provided for @tunnelLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tunnel logs'**
  String get tunnelLogsTitle;

  /// No description provided for @tunnelLogsLevelOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get tunnelLogsLevelOff;

  /// No description provided for @tunnelLogsLevelError.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get tunnelLogsLevelError;

  /// No description provided for @tunnelLogsLevelWarn.
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get tunnelLogsLevelWarn;

  /// No description provided for @tunnelLogsLevelInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get tunnelLogsLevelInfo;

  /// No description provided for @tunnelLogsLevelDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get tunnelLogsLevelDebug;

  /// No description provided for @tunnelLogsSearch.
  ///
  /// In en, this message translates to:
  /// **'Text, IP, or domain'**
  String get tunnelLogsSearch;

  /// No description provided for @tunnelLogsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tunnelLogsAll;

  /// No description provided for @tunnelLogsSession.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get tunnelLogsSession;

  /// No description provided for @tunnelLogsUi.
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get tunnelLogsUi;

  /// No description provided for @tunnelLogsCore.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get tunnelLogsCore;

  /// No description provided for @tunnelLogsDns.
  ///
  /// In en, this message translates to:
  /// **'DNS'**
  String get tunnelLogsDns;

  /// No description provided for @tunnelLogsFetch.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get tunnelLogsFetch;

  /// No description provided for @tunnelLogsNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get tunnelLogsNetwork;

  /// No description provided for @tunnelLogsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get tunnelLogsRefresh;

  /// No description provided for @tunnelLogsCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get tunnelLogsCopy;

  /// No description provided for @tunnelLogsExport.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get tunnelLogsExport;

  /// No description provided for @tunnelLogsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get tunnelLogsDelete;

  /// No description provided for @tunnelLogsClearBlocked.
  ///
  /// In en, this message translates to:
  /// **'Could not delete: {files}. Administrator rights are required.'**
  String tunnelLogsClearBlocked(String files);

  /// No description provided for @tunnelLogsCopied.
  ///
  /// In en, this message translates to:
  /// **'Log copied'**
  String get tunnelLogsCopied;

  /// No description provided for @tunnelLogsDebugFile.
  ///
  /// In en, this message translates to:
  /// **'File to send: {path}'**
  String tunnelLogsDebugFile(String path);

  /// No description provided for @tunnelLogsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No entries'**
  String get tunnelLogsEmpty;

  /// No description provided for @settingsSendReportHint.
  ///
  /// In en, this message translates to:
  /// **'Copies diagnostics. Paste them into support yourself.'**
  String get settingsSendReportHint;

  /// No description provided for @settingsSendReportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get settingsSendReportConfirm;

  /// No description provided for @settingsReportSent.
  ///
  /// In en, this message translates to:
  /// **'Report sent to support via the bot. Also copied.'**
  String get settingsReportSent;

  /// No description provided for @settingsReportCopied.
  ///
  /// In en, this message translates to:
  /// **'Report text copied'**
  String get settingsReportCopied;

  /// No description provided for @settingsReportSaved.
  ///
  /// In en, this message translates to:
  /// **'Report saved: {id}. Copied to clipboard.'**
  String settingsReportSaved(String id);

  /// No description provided for @settingsReportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t build the report'**
  String get settingsReportFailed;

  /// No description provided for @settingsReportUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Session expired — sign in again and retry'**
  String get settingsReportUnauthorized;

  /// No description provided for @settingsReportNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server — try again later'**
  String get settingsReportNetworkError;

  /// No description provided for @settingsVpnNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Shade notification'**
  String get settingsVpnNotificationTitle;

  /// No description provided for @settingsVpnNotificationHint.
  ///
  /// In en, this message translates to:
  /// **'Card in the shade with Disconnect. Off hides the card; VPN stays on.'**
  String get settingsVpnNotificationHint;

  /// No description provided for @settingsQsTileTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Settings tile'**
  String get settingsQsTileTitle;

  /// No description provided for @settingsQsTileHint.
  ///
  /// In en, this message translates to:
  /// **'Add a tile to connect and disconnect from Quick Settings'**
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

  /// No description provided for @settingsQsTileAddedHint.
  ///
  /// In en, this message translates to:
  /// **'The tile is in Quick Settings. Tap to remove it'**
  String get settingsQsTileAddedHint;

  /// No description provided for @settingsQsTileRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get settingsQsTileRemove;

  /// No description provided for @settingsQsTileRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the tile'**
  String get settingsQsTileRemoveTitle;

  /// No description provided for @settingsQsTileRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'Pull down the shade, tap the pencil, and drag the “Proxy Dom” tile to the trash.'**
  String get settingsQsTileRemoveBody;

  /// No description provided for @settingsQsTileRemoveAck.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get settingsQsTileRemoveAck;

  /// No description provided for @settingsQsTileManual.
  ///
  /// In en, this message translates to:
  /// **'Add manually: shade → pencil → “Proxy Dom”'**
  String get settingsQsTileManual;

  /// No description provided for @settingsQsTileNotAdded.
  ///
  /// In en, this message translates to:
  /// **'The tile was not added'**
  String get settingsQsTileNotAdded;

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
  /// **'Nearest available location'**
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

  /// No description provided for @regionSectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get regionSectionGeneral;

  /// No description provided for @regionSectionFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get regionSectionFree;

  /// No description provided for @regionSectionEurope.
  ///
  /// In en, this message translates to:
  /// **'Latvia'**
  String get regionSectionEurope;

  /// No description provided for @regionSectionUsa.
  ///
  /// In en, this message translates to:
  /// **'USA'**
  String get regionSectionUsa;

  /// No description provided for @regionComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get regionComingSoon;

  /// No description provided for @regionComingSoonBadge.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get regionComingSoonBadge;

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

  /// No description provided for @regionBlurbFree.
  ///
  /// In en, this message translates to:
  /// **'Apps and websites'**
  String get regionBlurbFree;

  /// No description provided for @regionBlurbGaming.
  ///
  /// In en, this message translates to:
  /// **'Low ping'**
  String get regionBlurbGaming;

  /// No description provided for @regionBlurbYoutube.
  ///
  /// In en, this message translates to:
  /// **'Comfortable streaming'**
  String get regionBlurbYoutube;

  /// No description provided for @regionBlurbIndia.
  ///
  /// In en, this message translates to:
  /// **'Apps and websites'**
  String get regionBlurbIndia;

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

  /// No description provided for @regionCachedHint.
  ///
  /// In en, this message translates to:
  /// **'Showing a saved list — network is unstable right now'**
  String get regionCachedHint;

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

  /// No description provided for @regionSwitchingTitle.
  ///
  /// In en, this message translates to:
  /// **'Switching location…'**
  String get regionSwitchingTitle;

  /// No description provided for @regionSwitchingBody.
  ///
  /// In en, this message translates to:
  /// **'Connecting to the selected server'**
  String get regionSwitchingBody;

  /// No description provided for @regionSwitchedTitle.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get regionSwitchedTitle;

  /// No description provided for @regionSwitchFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not switch location'**
  String get regionSwitchFailedTitle;

  /// No description provided for @logoutTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get logoutTooltip;

  /// No description provided for @settingsDeviceId.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get settingsDeviceId;

  /// No description provided for @settingsDeviceIdCopied.
  ///
  /// In en, this message translates to:
  /// **'Device ID copied'**
  String get settingsDeviceIdCopied;

  /// No description provided for @settingsDeviceIdHint.
  ///
  /// In en, this message translates to:
  /// **'Install identifier for support'**
  String get settingsDeviceIdHint;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Your VPN connection will be closed. Restore with your code or register again next time.'**
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

  /// No description provided for @navBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get navBack;

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

  /// No description provided for @welcomeHeadline.
  ///
  /// In en, this message translates to:
  /// **'A warm house on a cold internet'**
  String get welcomeHeadline;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'An account is created automatically. Then one tap for a protected connection.'**
  String get welcomeBody;

  /// No description provided for @welcomeContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get welcomeContinue;

  /// No description provided for @welcomeSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get welcomeSkip;

  /// No description provided for @referralShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite a friend'**
  String get referralShareTitle;

  /// No description provided for @referralShareBody.
  ///
  /// In en, this message translates to:
  /// **'They enter your code after install. Extra days land after they pay, not after install.'**
  String get referralShareBody;

  /// No description provided for @referralCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get referralCopy;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingDone.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingDone;

  /// No description provided for @onboardingConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get onboardingConnectTitle;

  /// No description provided for @onboardingConnectBody.
  ///
  /// In en, this message translates to:
  /// **'Tap Connect on Home. Android will ask for VPN permission once — that’s normal.'**
  String get onboardingConnectBody;

  /// No description provided for @onboardingConnectBodyIos.
  ///
  /// In en, this message translates to:
  /// **'Tap Connect on Home. iPhone will ask for VPN permission once — that’s normal.'**
  String get onboardingConnectBodyIos;

  /// No description provided for @onboardingRegionTitle.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get onboardingRegionTitle;

  /// No description provided for @onboardingRegionBody.
  ///
  /// In en, this message translates to:
  /// **'Automatic region is recommended. You can change it later in the list.'**
  String get onboardingRegionBody;

  /// No description provided for @onboardingHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help and privacy'**
  String get onboardingHelpTitle;

  /// No description provided for @onboardingHelpBody.
  ///
  /// In en, this message translates to:
  /// **'Send a diagnostic report from Settings if something breaks. We only collect a minimal daily aggregate — no browsing history, apps list, or ad IDs.'**
  String get onboardingHelpBody;

  /// No description provided for @betaGateError.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t check access. Check your connection.'**
  String get betaGateError;

  /// No description provided for @betaGateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking access…'**
  String get betaGateChecking;

  /// No description provided for @betaGateErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server did not respond. If VPN is on, turn it off and retry.'**
  String get betaGateErrorTimeout;

  /// No description provided for @betaGateErrorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Try again.'**
  String get betaGateErrorUnauthorized;

  /// No description provided for @betaGateDisconnectVpnRetry.
  ///
  /// In en, this message translates to:
  /// **'Disconnect VPN and retry'**
  String get betaGateDisconnectVpnRetry;

  /// No description provided for @betaGateContinueAnyway.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get betaGateContinueAnyway;

  /// No description provided for @lockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Activation'**
  String get lockedTitle;

  /// No description provided for @lockedHeadline.
  ///
  /// In en, this message translates to:
  /// **'Welcome!'**
  String get lockedHeadline;

  /// No description provided for @lockedRefreshAccess.
  ///
  /// In en, this message translates to:
  /// **'Refresh access'**
  String get lockedRefreshAccess;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupport;

  /// No description provided for @lockedPlan1m.
  ///
  /// In en, this message translates to:
  /// **'1 month'**
  String get lockedPlan1m;

  /// No description provided for @lockedPlan3m.
  ///
  /// In en, this message translates to:
  /// **'3 months'**
  String get lockedPlan3m;

  /// No description provided for @lockedPlan6m.
  ///
  /// In en, this message translates to:
  /// **'6 months'**
  String get lockedPlan6m;

  /// No description provided for @lockedPlan12m.
  ///
  /// In en, this message translates to:
  /// **'12 months'**
  String get lockedPlan12m;

  /// No description provided for @lockedSavePercent.
  ///
  /// In en, this message translates to:
  /// **'−{percent}%'**
  String lockedSavePercent(int percent);

  /// No description provided for @lockedVerifyCode.
  ///
  /// In en, this message translates to:
  /// **'Verification code: {code}'**
  String lockedVerifyCode(String code);

  /// No description provided for @settingsTerms.
  ///
  /// In en, this message translates to:
  /// **'Agreement'**
  String get settingsTerms;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// No description provided for @recoveryCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get recoveryCodeTitle;

  /// No description provided for @recoveryCodeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get recoveryCodeHeadline;

  /// No description provided for @recoveryCodeCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get recoveryCodeCopy;

  /// No description provided for @recoveryCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get recoveryCodeCopied;

  /// No description provided for @recoveryCodeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get recoveryCodeConfirm;

  /// No description provided for @recoveryCodeContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get recoveryCodeContinue;

  /// No description provided for @restoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore access'**
  String get restoreTitle;

  /// No description provided for @restoreHeadline.
  ///
  /// In en, this message translates to:
  /// **'Enter recovery code'**
  String get restoreHeadline;

  /// No description provided for @restorePaymentLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment ID'**
  String get restorePaymentLabel;

  /// No description provided for @restorePaymentHint.
  ///
  /// In en, this message translates to:
  /// **'UUID from the payment receipt'**
  String get restorePaymentHint;

  /// No description provided for @restorePaymentEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter the payment ID'**
  String get restorePaymentEmpty;

  /// No description provided for @restorePaymentNotFound.
  ///
  /// In en, this message translates to:
  /// **'Payment not found. Check the ID.'**
  String get restorePaymentNotFound;

  /// No description provided for @restorePaymentNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'This payment is not confirmed yet.'**
  String get restorePaymentNotConfirmed;

  /// No description provided for @restoreCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get restoreCodeLabel;

  /// No description provided for @restoreCodeHint.
  ///
  /// In en, this message translates to:
  /// **'TRM-XXXX-XXXX-XXXX'**
  String get restoreCodeHint;

  /// No description provided for @restoreCodeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery code'**
  String get restoreCodeEmpty;

  /// No description provided for @restoreSubmit.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreSubmit;

  /// No description provided for @restoreInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid recovery code'**
  String get restoreInvalid;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t restore access. Try again.'**
  String get restoreFailed;

  /// No description provided for @restoreDeviceLimitTitle.
  ///
  /// In en, this message translates to:
  /// **'Device limit reached'**
  String get restoreDeviceLimitTitle;

  /// No description provided for @restoreDeviceLimitBody.
  ///
  /// In en, this message translates to:
  /// **'Choose which device to disconnect so this device can join.'**
  String get restoreDeviceLimitBody;

  /// No description provided for @restoreAccountFull.
  ///
  /// In en, this message translates to:
  /// **'Device limit reached. Remove one in the device list, then sign in again. Devices already signed in stay online.'**
  String get restoreAccountFull;

  /// No description provided for @restoreDeviceLimitOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get restoreDeviceLimitOwner;

  /// No description provided for @restoreDeviceLimitPickFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t free a device slot. Try again.'**
  String get restoreDeviceLimitPickFailed;

  /// No description provided for @restoreSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'After reinstall — enter your recovery code'**
  String get restoreSettingsHint;

  /// No description provided for @restoreHeadlineCode.
  ///
  /// In en, this message translates to:
  /// **'Enter recovery code'**
  String get restoreHeadlineCode;

  /// No description provided for @settingsInviteDeviceHint.
  ///
  /// In en, this message translates to:
  /// **'Create a code to join your group'**
  String get settingsInviteDeviceHint;

  /// No description provided for @settingsAcceptSeat.
  ///
  /// In en, this message translates to:
  /// **'Join group'**
  String get settingsAcceptSeat;

  /// No description provided for @settingsAcceptSeatHint.
  ///
  /// In en, this message translates to:
  /// **'Join a subscription by invitation'**
  String get settingsAcceptSeatHint;

  /// No description provided for @settingsSeatCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Invitation code'**
  String get settingsSeatCodeTitle;

  /// No description provided for @settingsSeatCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get settingsSeatCodeCopied;

  /// No description provided for @settingsSeatInviteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t create an invitation code'**
  String get settingsSeatInviteFailed;

  /// No description provided for @settingsAcceptSeatOk.
  ///
  /// In en, this message translates to:
  /// **'Device added to the group'**
  String get settingsAcceptSeatOk;

  /// No description provided for @settingsSeatCodeNotFound.
  ///
  /// In en, this message translates to:
  /// **'Code not found or expired'**
  String get settingsSeatCodeNotFound;

  /// No description provided for @settingsSeatOwnCode.
  ///
  /// In en, this message translates to:
  /// **'You can’t accept your own code — enter it on another device'**
  String get settingsSeatOwnCode;

  /// No description provided for @settingsSeatAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t join the group'**
  String get settingsSeatAcceptFailed;

  /// No description provided for @settingsSeatCodeTtl.
  ///
  /// In en, this message translates to:
  /// **'Code is valid for 30 minutes'**
  String get settingsSeatCodeTtl;

  /// No description provided for @settingsSeatShowQr.
  ///
  /// In en, this message translates to:
  /// **'Show code'**
  String get settingsSeatShowQr;

  /// No description provided for @settingsSeatScanHint.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code or follow the link'**
  String get settingsSeatScanHint;

  /// No description provided for @seatAcceptConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Join this group?'**
  String get seatAcceptConsentTitle;

  /// No description provided for @seatAcceptConsentBody.
  ///
  /// In en, this message translates to:
  /// **'The account owner will see this device’s name, platform, and the date it was added. You can leave the group later.'**
  String get seatAcceptConsentBody;

  /// No description provided for @seatAcceptConsentConfirm.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get seatAcceptConsentConfirm;

  /// No description provided for @devicesOwnerCannotLeave.
  ///
  /// In en, this message translates to:
  /// **'Revoke other devices before leaving'**
  String get devicesOwnerCannotLeave;

  /// No description provided for @settingsRecoverAccess.
  ///
  /// In en, this message translates to:
  /// **'Restore access'**
  String get settingsRecoverAccess;

  /// No description provided for @settingsRecoverAccessHint.
  ///
  /// In en, this message translates to:
  /// **'Use recovery code after reinstall'**
  String get settingsRecoverAccessHint;

  /// No description provided for @bootstrapFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t start the session. Check your connection.'**
  String get bootstrapFailed;

  /// No description provided for @accountEmailLead.
  ///
  /// In en, this message translates to:
  /// **'Enter your email — we’ll send a one-time code.'**
  String get accountEmailLead;

  /// No description provided for @accountEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountEmailLabel;

  /// No description provided for @accountEmailSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get accountEmailSendCode;

  /// No description provided for @accountEmailCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code from email'**
  String get accountEmailCodeLabel;

  /// No description provided for @accountEmailVerify.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get accountEmailVerify;

  /// No description provided for @accountEmailChangeAddress.
  ///
  /// In en, this message translates to:
  /// **'Different address'**
  String get accountEmailChangeAddress;

  /// No description provided for @accountEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get accountEmailInvalid;

  /// No description provided for @accountEmailSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t send the code'**
  String get accountEmailSendFailed;

  /// No description provided for @accountEmailCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the code from email'**
  String get accountEmailCodeRequired;

  /// No description provided for @accountEmailVerifyFailed.
  ///
  /// In en, this message translates to:
  /// **'Invalid or expired code'**
  String get accountEmailVerifyFailed;

  /// No description provided for @accountEmailDebugHint.
  ///
  /// In en, this message translates to:
  /// **'DEBUG: code filled from API response'**
  String get accountEmailDebugHint;

  /// No description provided for @navPromo.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get navPromo;

  /// No description provided for @iosBillingUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'In-app payment is not available. Free locations still work.'**
  String get iosBillingUnavailableBody;

  /// No description provided for @iosAdvancedFeaturesCta.
  ///
  /// In en, this message translates to:
  /// **'Advanced features'**
  String get iosAdvancedFeaturesCta;

  /// No description provided for @vpnDisclosureTitle.
  ///
  /// In en, this message translates to:
  /// **'How the tunnel starts'**
  String get vpnDisclosureTitle;

  /// No description provided for @vpnDisclosureLead.
  ///
  /// In en, this message translates to:
  /// **'The house starts a tunnel from the line you chose. This screen explains that before Android asks for VPN permission.'**
  String get vpnDisclosureLead;

  /// No description provided for @vpnDisclosureVpnTitle.
  ///
  /// In en, this message translates to:
  /// **'What the app does'**
  String get vpnDisclosureVpnTitle;

  /// No description provided for @vpnDisclosureVpnBody.
  ///
  /// In en, this message translates to:
  /// **'After you accept, the house opens a local tunnel for the selected line. Device traffic goes to the server in that line. Android then shows its own VPN permission once.'**
  String get vpnDisclosureVpnBody;

  /// No description provided for @vpnDisclosureVpnTitleIos.
  ///
  /// In en, this message translates to:
  /// **'What the app does'**
  String get vpnDisclosureVpnTitleIos;

  /// No description provided for @vpnDisclosureVpnBodyIos.
  ///
  /// In en, this message translates to:
  /// **'After you accept, the house opens a local tunnel for the selected line. Device traffic goes to the server in that line. iPhone then shows its own VPN permission once.'**
  String get vpnDisclosureVpnBodyIos;

  /// No description provided for @vpnDisclosureDataTitle.
  ///
  /// In en, this message translates to:
  /// **'What stays on the phone'**
  String get vpnDisclosureDataTitle;

  /// No description provided for @vpnDisclosureDataBody.
  ///
  /// In en, this message translates to:
  /// **'The access line stays on the device. A diagnostic report leaves the phone only if you send it from Settings. Browsing history is not recorded.'**
  String get vpnDisclosureDataBody;

  /// No description provided for @vpnDisclosureDataBodyIos.
  ///
  /// In en, this message translates to:
  /// **'The access line stays on the device. A diagnostic report leaves the phone only if you send it from Settings. Browsing history is not recorded.'**
  String get vpnDisclosureDataBodyIos;

  /// No description provided for @vpnDisclosureNotTitle.
  ///
  /// In en, this message translates to:
  /// **'What the app does not do'**
  String get vpnDisclosureNotTitle;

  /// No description provided for @vpnDisclosureNotBody.
  ///
  /// In en, this message translates to:
  /// **'It does not keep a history of sites and it does not read an advertising ID. It does not sell access or hand out servers: you bring the line.'**
  String get vpnDisclosureNotBody;

  /// No description provided for @vpnDisclosureAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept and continue'**
  String get vpnDisclosureAccept;

  /// No description provided for @vpnDisclosureDecline.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get vpnDisclosureDecline;

  /// No description provided for @freeAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get freeAdd;

  /// No description provided for @freePaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get freePaste;

  /// No description provided for @freeQr.
  ///
  /// In en, this message translates to:
  /// **'QR'**
  String get freeQr;

  /// No description provided for @freeAddServer.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get freeAddServer;

  /// No description provided for @freeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No servers added'**
  String get freeEmptyTitle;

  /// No description provided for @freeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add a link, a key, or a QR code.'**
  String get freeEmptyBody;

  /// No description provided for @freeStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get freeStatus;

  /// No description provided for @freeProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get freeProfile;

  /// No description provided for @freeProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get freeProtocol;

  /// No description provided for @freeTrafficLeft.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get freeTrafficLeft;

  /// No description provided for @freeUptime.
  ///
  /// In en, this message translates to:
  /// **'Uptime'**
  String get freeUptime;

  /// No description provided for @freeNoProfile.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get freeNoProfile;

  /// No description provided for @freeAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get freeAddTitle;

  /// No description provided for @freeAddHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a link or a key.'**
  String get freeAddHint;

  /// No description provided for @freeSaveConnect.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get freeSaveConnect;

  /// No description provided for @freeSaveOnly.
  ///
  /// In en, this message translates to:
  /// **'Save only'**
  String get freeSaveOnly;

  /// No description provided for @freePreview.
  ///
  /// In en, this message translates to:
  /// **'Found'**
  String get freePreview;

  /// No description provided for @freeServerAdded.
  ///
  /// In en, this message translates to:
  /// **'Server added'**
  String get freeServerAdded;

  /// No description provided for @freeImportCount.
  ///
  /// In en, this message translates to:
  /// **'Read {recognized}, unsupported {unsupported}'**
  String freeImportCount(int recognized, int unsupported);

  /// No description provided for @freeLinkInvalid.
  ///
  /// In en, this message translates to:
  /// **'Could not read that link'**
  String get freeLinkInvalid;

  /// No description provided for @freeSubscriptionLoadFail.
  ///
  /// In en, this message translates to:
  /// **'The document did not load. The host did not answer.'**
  String get freeSubscriptionLoadFail;

  /// No description provided for @freeSubscriptionMissing.
  ///
  /// In en, this message translates to:
  /// **'That address has no document.'**
  String get freeSubscriptionMissing;

  /// No description provided for @freeSubscriptionDeviceLimit.
  ///
  /// In en, this message translates to:
  /// **'This document has no free device slots. Free one and refresh the list.'**
  String get freeSubscriptionDeviceLimit;

  /// No description provided for @freeSubscriptionClientRefused.
  ///
  /// In en, this message translates to:
  /// **'The document sent a placeholder instead of a server.'**
  String get freeSubscriptionClientRefused;

  /// No description provided for @freeSharePool.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get freeSharePool;

  /// No description provided for @freeShareCopied.
  ///
  /// In en, this message translates to:
  /// **'Key copied'**
  String get freeShareCopied;

  /// No description provided for @freeShareFail.
  ///
  /// In en, this message translates to:
  /// **'Could not create the link'**
  String get freeShareFail;

  /// No description provided for @freeOnboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Server list'**
  String get freeOnboardTitle;

  /// No description provided for @freeOnboardBody.
  ///
  /// In en, this message translates to:
  /// **'An address or a key becomes a profile. Its servers stay in one list.'**
  String get freeOnboardBody;

  /// No description provided for @freeOnboardAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a server'**
  String get freeOnboardAddTitle;

  /// No description provided for @freeOnboardAddBody.
  ///
  /// In en, this message translates to:
  /// **'Each server has a name and a short line. You choose which one to use.'**
  String get freeOnboardAddBody;

  /// No description provided for @freeOnboardConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect with one tap'**
  String get freeOnboardConnectTitle;

  /// No description provided for @freeOnboardConnectBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the house to connect or disconnect. The status stays on this screen.'**
  String get freeOnboardConnectBody;

  /// No description provided for @freeLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get freeLater;

  /// No description provided for @freeBatteryTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep the tunnel running'**
  String get freeBatteryTitle;

  /// No description provided for @freeBatteryBody.
  ///
  /// In en, this message translates to:
  /// **'Android may stop the tunnel to save battery. You can allow background activity.'**
  String get freeBatteryBody;

  /// No description provided for @freeBatteryAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get freeBatteryAllow;

  /// No description provided for @freeBatteryDismiss.
  ///
  /// In en, this message translates to:
  /// **'Don\'t ask again'**
  String get freeBatteryDismiss;

  /// No description provided for @freeServers.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get freeServers;

  /// No description provided for @freePoolMarked.
  ///
  /// In en, this message translates to:
  /// **'Marked'**
  String get freePoolMarked;

  /// No description provided for @freeIosHy2Only.
  ///
  /// In en, this message translates to:
  /// **'This protocol cannot start.'**
  String get freeIosHy2Only;

  /// No description provided for @freeHy2OnlyAdd.
  ///
  /// In en, this message translates to:
  /// **'Could not add the node: this protocol cannot start on this device.'**
  String get freeHy2OnlyAdd;

  /// No description provided for @freeNoHy2Lines.
  ///
  /// In en, this message translates to:
  /// **'This source has no lines the client can start.'**
  String get freeNoHy2Lines;

  /// No description provided for @freeSchemeParked.
  ///
  /// In en, this message translates to:
  /// **'This protocol cannot start.'**
  String get freeSchemeParked;

  /// No description provided for @freePoolGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get freePoolGeneral;

  /// No description provided for @freeSearch.
  ///
  /// In en, this message translates to:
  /// **'Search servers'**
  String get freeSearch;

  /// No description provided for @locationsNodes.
  ///
  /// In en, this message translates to:
  /// **'Nodes'**
  String get locationsNodes;

  /// No description provided for @locationsSelected.
  ///
  /// In en, this message translates to:
  /// **'IN USE'**
  String get locationsSelected;

  /// No description provided for @locationsActive.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get locationsActive;

  /// No description provided for @locationsNotUsed.
  ///
  /// In en, this message translates to:
  /// **'NOT USED'**
  String get locationsNotUsed;

  /// No description provided for @locationsUseIt.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get locationsUseIt;

  /// No description provided for @locationsInUse.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get locationsInUse;

  /// No description provided for @locationsShareKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get locationsShareKey;

  /// No description provided for @freeTelegram.
  ///
  /// In en, this message translates to:
  /// **'Telegram'**
  String get freeTelegram;

  /// No description provided for @locationsKeyHandle.
  ///
  /// In en, this message translates to:
  /// **'key'**
  String get locationsKeyHandle;

  /// No description provided for @freeDelete.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get freeDelete;

  /// No description provided for @freeDeleteServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this server?'**
  String get freeDeleteServerTitle;

  /// No description provided for @freeDeleteServerBody.
  ///
  /// In en, this message translates to:
  /// **'The link is deleted from this phone.'**
  String get freeDeleteServerBody;

  /// No description provided for @freeDeleteCatalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this list?'**
  String get freeDeleteCatalogTitle;

  /// No description provided for @freeDeleteCatalogBody.
  ///
  /// In en, this message translates to:
  /// **'Every server in the list is deleted from this phone.'**
  String get freeDeleteCatalogBody;

  /// No description provided for @freeRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get freeRefresh;

  /// No description provided for @freeRefreshDone.
  ///
  /// In en, this message translates to:
  /// **'Updated: {count}'**
  String freeRefreshDone(int count);

  /// No description provided for @freeRefreshFail.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh'**
  String get freeRefreshFail;

  /// No description provided for @freeStepLink.
  ///
  /// In en, this message translates to:
  /// **'LINK'**
  String get freeStepLink;

  /// No description provided for @freeStepFound.
  ///
  /// In en, this message translates to:
  /// **'FOUND'**
  String get freeStepFound;

  /// No description provided for @freeFieldEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty for now. Paste a link and we will see what is inside.'**
  String get freeFieldEmpty;
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
      'that was used.');
}
