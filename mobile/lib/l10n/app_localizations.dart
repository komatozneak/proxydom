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

  /// No description provided for @homeRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get homeRegion;

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

  /// No description provided for @homeAddServer.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get homeAddServer;

  /// No description provided for @homeMetricTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get homeMetricTime;

  /// No description provided for @homeMetricTraffic.
  ///
  /// In en, this message translates to:
  /// **'Traffic'**
  String get homeMetricTraffic;

  /// No description provided for @homeTrafficUnlimited.
  ///
  /// In en, this message translates to:
  /// **'UNLIMITED'**
  String get homeTrafficUnlimited;

  /// No description provided for @profileTrafficRemaining.
  ///
  /// In en, this message translates to:
  /// **'remaining'**
  String get profileTrafficRemaining;

  /// No description provided for @profileTrafficUsed.
  ///
  /// In en, this message translates to:
  /// **'used'**
  String get profileTrafficUsed;

  /// No description provided for @profileTrafficNoData.
  ///
  /// In en, this message translates to:
  /// **'no limit data'**
  String get profileTrafficNoData;

  /// No description provided for @profileTrafficStale.
  ///
  /// In en, this message translates to:
  /// **'stale'**
  String get profileTrafficStale;

  /// No description provided for @profileTrafficExpires.
  ///
  /// In en, this message translates to:
  /// **'expires'**
  String get profileTrafficExpires;

  /// No description provided for @profileSourceLocal.
  ///
  /// In en, this message translates to:
  /// **'local import'**
  String get profileSourceLocal;

  /// No description provided for @homeNoVpnRow.
  ///
  /// In en, this message translates to:
  /// **'Routing'**
  String get homeNoVpnRow;

  /// No description provided for @settingsNoVpn.
  ///
  /// In en, this message translates to:
  /// **'Routing'**
  String get settingsNoVpn;

  /// No description provided for @settingsNoVpnHint.
  ///
  /// In en, this message translates to:
  /// **'Split-tunnel rules for apps and sites'**
  String get settingsNoVpnHint;

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

  /// No description provided for @homeStatPingPending.
  ///
  /// In en, this message translates to:
  /// **'measuring'**
  String get homeStatPingPending;

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
  /// **'Another tunnel is blocking'**
  String get homeVpnConflictTitle;

  /// No description provided for @homeVpnConflictHint.
  ///
  /// In en, this message translates to:
  /// **'Turn off the other tunnel in Android settings, then connect again.'**
  String get homeVpnConflictHint;

  /// No description provided for @homeVpnConflictHintIos.
  ///
  /// In en, this message translates to:
  /// **'Turn off the other tunnel in Settings → VPN.'**
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
  /// **'Allow the tunnel in the Android system prompt, then tap connect again.'**
  String get homeVpnPermissionHint;

  /// No description provided for @homeVpnPermissionHintIos.
  ///
  /// In en, this message translates to:
  /// **'Allow the tunnel in the system prompt, then connect again.'**
  String get homeVpnPermissionHintIos;

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

  /// No description provided for @settingsKillSwitchOpenVpn.
  ///
  /// In en, this message translates to:
  /// **'Open tunnel settings'**
  String get settingsKillSwitchOpenVpn;

  /// No description provided for @settingsKillSwitchOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open tunnel settings. Open Settings → Network & internet → VPN.'**
  String get settingsKillSwitchOpenFailed;

  /// No description provided for @settingsKillSwitchOpenFailedIos.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open tunnel settings. Open Settings → VPN.'**
  String get settingsKillSwitchOpenFailedIos;

  /// No description provided for @splitTunnelSitesLead.
  ///
  /// In en, this message translates to:
  /// **'Listed sites use your usual connection, not the protected one. Everything else still goes through Proxy Dom.'**
  String get splitTunnelSitesLead;

  /// No description provided for @splitTunnelCustomSection.
  ///
  /// In en, this message translates to:
  /// **'My sites'**
  String get splitTunnelCustomSection;

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
  /// **'gw.company-net.ru'**
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

  /// No description provided for @splitTunnelEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get splitTunnelEdit;

  /// No description provided for @splitTunnelEditDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get splitTunnelEditDone;

  /// No description provided for @splitTunnelPlayersFound.
  ///
  /// In en, this message translates to:
  /// **'Players found: {count}'**
  String splitTunnelPlayersFound(int count);

  /// No description provided for @splitTunnelPlayersCount.
  ///
  /// In en, this message translates to:
  /// **'Players: {count}'**
  String splitTunnelPlayersCount(int count);

  /// No description provided for @splitTunnelEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add an exact hostname — only that address skips the tunnel, not its subdomains.'**
  String get splitTunnelEmptyBody;

  /// No description provided for @splitTunnelInvalidDomain.
  ///
  /// In en, this message translates to:
  /// **'Enter an address like gw.company-net.ru'**
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
  /// **'Android lockdown mode is on. Apps in this list may have no internet until you turn it off or return them to the tunnel.'**
  String get splitTunnelAppsLockdownWarning;

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

  /// No description provided for @settingsPrivacyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get settingsPrivacyPlaceholder;

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

  /// No description provided for @licensesTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Source Notices'**
  String get licensesTitle;

  /// No description provided for @licensesSearch.
  ///
  /// In en, this message translates to:
  /// **'Search packages'**
  String get licensesSearch;

  /// No description provided for @licensesEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get licensesEngine;

  /// No description provided for @licensesPackages.
  ///
  /// In en, this message translates to:
  /// **'Packages'**
  String get licensesPackages;

  /// No description provided for @licensesFonts.
  ///
  /// In en, this message translates to:
  /// **'Fonts'**
  String get licensesFonts;

  /// No description provided for @licensesNoResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get licensesNoResults;

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

  /// No description provided for @settingsVpnNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Shade notification'**
  String get settingsVpnNotificationTitle;

  /// No description provided for @settingsVpnNotificationShort.
  ///
  /// In en, this message translates to:
  /// **'Shade card with Disconnect'**
  String get settingsVpnNotificationShort;

  /// No description provided for @settingsVpnNotificationHint.
  ///
  /// In en, this message translates to:
  /// **'Card in the shade with Disconnect. Off hides the card; the tunnel stays on.'**
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

  /// No description provided for @settingsQsTileAdded.
  ///
  /// In en, this message translates to:
  /// **'Tile added to Quick Settings'**
  String get settingsQsTileAdded;

  /// No description provided for @settingsQsTileAddedHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to remove'**
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

  /// No description provided for @homeSessionLabel.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get homeSessionLabel;

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

  /// No description provided for @onboardingConnectBody.
  ///
  /// In en, this message translates to:
  /// **'Tap Connect on Home. Android will ask for tunnel permission once — that’s normal.'**
  String get onboardingConnectBody;

  /// No description provided for @onboardingConnectBodyIos.
  ///
  /// In en, this message translates to:
  /// **'Tap Connect on Home. iPhone will ask for tunnel permission once — that’s normal.'**
  String get onboardingConnectBodyIos;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupport;

  /// No description provided for @vpnDisclosureTitle.
  ///
  /// In en, this message translates to:
  /// **'How the tunnel starts'**
  String get vpnDisclosureTitle;

  /// No description provided for @vpnDisclosureBullet1.
  ///
  /// In en, this message translates to:
  /// **'The tunnel starts only on your command and only on this device.'**
  String get vpnDisclosureBullet1;

  /// No description provided for @vpnDisclosureBullet2.
  ///
  /// In en, this message translates to:
  /// **'Keys and node addresses are never sent to a server.'**
  String get vpnDisclosureBullet2;

  /// No description provided for @vpnDisclosureBullet3.
  ///
  /// In en, this message translates to:
  /// **'No account, no payments, no ads.'**
  String get vpnDisclosureBullet3;

  /// No description provided for @vpnDisclosureMore.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get vpnDisclosureMore;

  /// No description provided for @vpnDisclosureClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get vpnDisclosureClose;

  /// No description provided for @vpnDisclosureLead.
  ///
  /// In en, this message translates to:
  /// **'The app starts a tunnel for the selected line. Android will ask for tunnel permission once.'**
  String get vpnDisclosureLead;

  /// No description provided for @vpnDisclosureVpnTitle.
  ///
  /// In en, this message translates to:
  /// **'What the app does'**
  String get vpnDisclosureVpnTitle;

  /// No description provided for @vpnDisclosureVpnBody.
  ///
  /// In en, this message translates to:
  /// **'After you agree, the app brings up a local tunnel for the selected line. Traffic goes to the server in that line. Android asks for tunnel permission once.'**
  String get vpnDisclosureVpnBody;

  /// No description provided for @vpnDisclosureVpnTitleIos.
  ///
  /// In en, this message translates to:
  /// **'What the app does'**
  String get vpnDisclosureVpnTitleIos;

  /// No description provided for @vpnDisclosureVpnBodyIos.
  ///
  /// In en, this message translates to:
  /// **'After you agree, the app brings up a local tunnel for the selected line. Traffic goes to the server in that line. iPhone asks for tunnel permission once.'**
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
  /// **'An address or a key becomes a profile. Its nodes stay in one list: Moscow (Primary), St Petersburg (Backup), Novosibirsk (Low ping).'**
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
  /// **'Tap the connect button in the centre of the screen. It turns the tunnel on and off. The status stays on this screen.'**
  String get freeOnboardConnectBody;

  /// No description provided for @pcOnboardHeadline.
  ///
  /// In en, this message translates to:
  /// **'Connect on this PC'**
  String get pcOnboardHeadline;

  /// No description provided for @pcOnboardBody.
  ///
  /// In en, this message translates to:
  /// **'Paste an access key or a document link. The app will show the nodes it contains, for example gw.company-net.ru.'**
  String get pcOnboardBody;

  /// No description provided for @pcOnboardPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Keys and server addresses stay on this computer.'**
  String get pcOnboardPrivacy;

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

  /// No description provided for @freeSearch.
  ///
  /// In en, this message translates to:
  /// **'Search servers'**
  String get freeSearch;

  /// No description provided for @freeSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No servers found'**
  String get freeSearchEmpty;

  /// No description provided for @qrHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code'**
  String get qrHint;

  /// No description provided for @qrTorch.
  ///
  /// In en, this message translates to:
  /// **'Torch'**
  String get qrTorch;

  /// No description provided for @locationsNodes.
  ///
  /// In en, this message translates to:
  /// **'Nodes'**
  String get locationsNodes;

  /// No description provided for @locationsActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get locationsActive;

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
  /// **'The link is deleted from this device.'**
  String get freeDeleteServerBody;

  /// No description provided for @freeDeleteCatalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this list?'**
  String get freeDeleteCatalogTitle;

  /// No description provided for @freeDeleteCatalogBody.
  ///
  /// In en, this message translates to:
  /// **'Every server in the list is deleted from this device.'**
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
  /// **'Link'**
  String get freeStepLink;

  /// No description provided for @freeStepFound.
  ///
  /// In en, this message translates to:
  /// **'Found'**
  String get freeStepFound;

  /// No description provided for @freeFoundEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nodes from the link will appear here — for example Moscow (Primary) or St Petersburg (Backup).'**
  String get freeFoundEmpty;

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
