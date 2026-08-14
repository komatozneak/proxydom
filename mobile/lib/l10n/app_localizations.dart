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
  /// **'Tap Teremok to connect'**
  String get homeTapHint;

  /// No description provided for @homeConnectingHint.
  ///
  /// In en, this message translates to:
  /// **'Hold on — Teremok is opening the door…'**
  String get homeConnectingHint;

  /// No description provided for @homeConnectedHint.
  ///
  /// In en, this message translates to:
  /// **'Teremok is online'**
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
  /// **'VPN'**
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

  /// No description provided for @navSubscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get navSubscription;

  /// No description provided for @navPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get navPremium;

  /// No description provided for @homeTrafficRemainder.
  ///
  /// In en, this message translates to:
  /// **'Data left'**
  String get homeTrafficRemainder;

  /// No description provided for @homeNoVpnRow.
  ///
  /// In en, this message translates to:
  /// **'What works without VPN?'**
  String get homeNoVpnRow;

  /// No description provided for @premiumHeadline.
  ///
  /// In en, this message translates to:
  /// **'YouTube without ads'**
  String get premiumHeadline;

  /// No description provided for @premiumBody.
  ///
  /// In en, this message translates to:
  /// **'Premium unlocks no-AdSense exits, up to 5 devices, and removes the free 4.20 GB cap.'**
  String get premiumBody;

  /// No description provided for @premiumFeatureYt.
  ///
  /// In en, this message translates to:
  /// **'YouTube locations without mid-roll ads'**
  String get premiumFeatureYt;

  /// No description provided for @premiumFeatureSpeed.
  ///
  /// In en, this message translates to:
  /// **'Priority exits for streaming'**
  String get premiumFeatureSpeed;

  /// No description provided for @premiumUnlimitedTraffic.
  ///
  /// In en, this message translates to:
  /// **'Unlimited traffic'**
  String get premiumUnlimitedTraffic;

  /// No description provided for @premiumCta.
  ///
  /// In en, this message translates to:
  /// **'Get Premium'**
  String get premiumCta;

  /// No description provided for @premiumOpenLocations.
  ///
  /// In en, this message translates to:
  /// **'Open locations'**
  String get premiumOpenLocations;

  /// No description provided for @subscriptionTabHint.
  ///
  /// In en, this message translates to:
  /// **'Manage plans and promo codes. Premium unlocks YouTube locations.'**
  String get subscriptionTabHint;

  /// No description provided for @locationsPremiumLocked.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get locationsPremiumLocked;

  /// No description provided for @locationsPremiumUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Available with Premium'**
  String get locationsPremiumUnavailable;

  /// No description provided for @settingsNoVpn.
  ///
  /// In en, this message translates to:
  /// **'What works without VPN?'**
  String get settingsNoVpn;

  /// No description provided for @settingsNoVpnHint.
  ///
  /// In en, this message translates to:
  /// **'These addresses open directly, bypassing the VPN'**
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

  /// No description provided for @homeQuotaExceededTitle.
  ///
  /// In en, this message translates to:
  /// **'Free traffic used up'**
  String get homeQuotaExceededTitle;

  /// No description provided for @homeQuotaExceededHint.
  ///
  /// In en, this message translates to:
  /// **'You’ve used this month’s 4.20 GB. Upgrade to Premium for unlimited traffic.'**
  String get homeQuotaExceededHint;

  /// No description provided for @homeQuotaUpgradeCta.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get homeQuotaUpgradeCta;

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
  /// **'Turn off the other VPN or Always-on in Android settings, then connect again.'**
  String get homeVpnConflictHint;

  /// No description provided for @homeVpnConflictHintNamed.
  ///
  /// In en, this message translates to:
  /// **'Turn off “{app}” (or Always-on) in Android settings, then connect again.'**
  String homeVpnConflictHintNamed(String app);

  /// No description provided for @homeVpnPermissionHint.
  ///
  /// In en, this message translates to:
  /// **'Allow the VPN in the Android system prompt, then tap connect again.'**
  String get homeVpnPermissionHint;

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
  /// **'Premium'**
  String get settingsAccessEarlyTitle;

  /// No description provided for @settingsAccessEarlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Access is by invite.'**
  String get settingsAccessEarlySubtitle;

  /// No description provided for @settingsAccessBetaTitle.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get settingsAccessBetaTitle;

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

  /// No description provided for @settingsAccessFreeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'1 device · up to 4.20 GB per month.'**
  String get settingsAccessFreeSubtitle;

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
  /// **'Premium'**
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
  /// **'Block connections without VPN'**
  String get settingsKillSwitch;

  /// No description provided for @settingsKillSwitchHint.
  ///
  /// In en, this message translates to:
  /// **'Android blocks internet access while the protected connection is unavailable.'**
  String get settingsKillSwitchHint;

  /// No description provided for @settingsKillSwitchHintSystem.
  ///
  /// In en, this message translates to:
  /// **'Enable Always-on VPN and Block connections without VPN in system VPN settings'**
  String get settingsKillSwitchHintSystem;

  /// No description provided for @settingsKillSwitchOn.
  ///
  /// In en, this message translates to:
  /// **'Enabled in Android settings'**
  String get settingsKillSwitchOn;

  /// No description provided for @settingsKillSwitchAlwaysOnOnly.
  ///
  /// In en, this message translates to:
  /// **'Always-on is on — also enable “Block connections without VPN”'**
  String get settingsKillSwitchAlwaysOnOnly;

  /// No description provided for @settingsKillSwitchOff.
  ///
  /// In en, this message translates to:
  /// **'Off — internet may work without VPN'**
  String get settingsKillSwitchOff;

  /// No description provided for @settingsKillSwitchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check the Android setting'**
  String get settingsKillSwitchUnavailable;

  /// No description provided for @settingsKillSwitchChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking Android setting…'**
  String get settingsKillSwitchChecking;

  /// No description provided for @settingsKillSwitchOpenVpn.
  ///
  /// In en, this message translates to:
  /// **'Open VPN settings'**
  String get settingsKillSwitchOpenVpn;

  /// No description provided for @settingsKillSwitchRisk.
  ///
  /// In en, this message translates to:
  /// **'If the connection cannot recover, internet stays unavailable until you turn this off in Android settings.'**
  String get settingsKillSwitchRisk;

  /// No description provided for @settingsKillSwitchOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open VPN settings. Open Settings → Network & internet → VPN.'**
  String get settingsKillSwitchOpenFailed;

  /// No description provided for @settingsKillSwitchAndroidOwned.
  ///
  /// In en, this message translates to:
  /// **'Controlled by Android'**
  String get settingsKillSwitchAndroidOwned;

  /// No description provided for @settingsKillSwitchBadgeOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingsKillSwitchBadgeOn;

  /// No description provided for @settingsKillSwitchBadgePartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get settingsKillSwitchBadgePartial;

  /// No description provided for @settingsKillSwitchBadgeOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsKillSwitchBadgeOff;

  /// No description provided for @settingsKillSwitchBadgeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get settingsKillSwitchBadgeUnknown;

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
  /// **'Each app install gets its own VPN key. You can revoke access for a single device.'**
  String get devicesHint;

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

  /// No description provided for @devicesThisDevice.
  ///
  /// In en, this message translates to:
  /// **'this device'**
  String get devicesThisDevice;

  /// No description provided for @devicesRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
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

  /// No description provided for @devicesLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave account'**
  String get devicesLeave;

  /// No description provided for @devicesLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave shared account?'**
  String get devicesLeaveTitle;

  /// No description provided for @devicesLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'This install becomes its own account. Subscription stays on the old account. Save any new recovery code if shown.'**
  String get devicesLeaveBody;

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
  /// **'Built into the app — one tap to enable.'**
  String get splitTunnelBundledLead;

  /// No description provided for @splitTunnelBundledRuTitle.
  ///
  /// In en, this message translates to:
  /// **'Direct access for Russia'**
  String get splitTunnelBundledRuTitle;

  /// No description provided for @splitTunnelBundledRuSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Russian sites and services\n.ru, .su and .рф domains\nIP addresses in Russia'**
  String get splitTunnelBundledRuSubtitle;

  /// No description provided for @splitTunnelBundledInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get splitTunnelBundledInfoTitle;

  /// No description provided for @splitTunnelBundledInfoBody.
  ///
  /// In en, this message translates to:
  /// **'This list ships inside Teremok and really changes routing.\n\nThe ready-made list includes:\n• Russian sites and services\n• all .ru, .su and .рф domains\n• IP addresses in Russia\n\nOn — this traffic bypasses the VPN.\nOff — all traffic uses the VPN.\n\nIf VPN is already connected, tap Reconnect after changing.'**
  String get splitTunnelBundledInfoBody;

  /// No description provided for @splitTunnelBundledInfoClose.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get splitTunnelBundledInfoClose;

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
  /// **'Add an address — it will open directly, without the VPN.'**
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
  /// **'Couldn\'t send the report'**
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
  /// **'EU Hy2 → US Hy2'**
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

  /// No description provided for @regionSectionYoutube.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get regionSectionYoutube;

  /// No description provided for @regionSectionFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get regionSectionFree;

  /// No description provided for @regionSectionEurope.
  ///
  /// In en, this message translates to:
  /// **'Europe'**
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
  /// **'Hysteria2 · apps, AI, websites'**
  String get regionBlurbFree;

  /// No description provided for @regionBlurbGaming.
  ///
  /// In en, this message translates to:
  /// **'TrustTunnel · low ping'**
  String get regionBlurbGaming;

  /// No description provided for @regionBlurbYoutube.
  ///
  /// In en, this message translates to:
  /// **'TrustTunnel · ad-free'**
  String get regionBlurbYoutube;

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

  /// No description provided for @navBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get navBack;

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

  /// No description provided for @welcomeHeadline.
  ///
  /// In en, this message translates to:
  /// **'A warm house on a cold internet'**
  String get welcomeHeadline;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your phone, then connect in one tap.'**
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

  /// No description provided for @promoTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get promoTitle;

  /// No description provided for @promoHeadline.
  ///
  /// In en, this message translates to:
  /// **'Enter your personal code'**
  String get promoHeadline;

  /// No description provided for @promoBody.
  ///
  /// In en, this message translates to:
  /// **'Access is by invite during the closed beta. You can retry without signing out.'**
  String get promoBody;

  /// No description provided for @promoCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get promoCodeLabel;

  /// No description provided for @promoCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Your invite code'**
  String get promoCodeHint;

  /// No description provided for @promoCodeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter a code'**
  String get promoCodeEmpty;

  /// No description provided for @promoSubmit.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get promoSubmit;

  /// No description provided for @promoOutcomeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Code not found. Check it and try again.'**
  String get promoOutcomeInvalid;

  /// No description provided for @promoOutcomeExpired.
  ///
  /// In en, this message translates to:
  /// **'This code has expired.'**
  String get promoOutcomeExpired;

  /// No description provided for @promoOutcomeExhausted.
  ///
  /// In en, this message translates to:
  /// **'This code has already been used.'**
  String get promoOutcomeExhausted;

  /// No description provided for @promoOutcomeRevoked.
  ///
  /// In en, this message translates to:
  /// **'This code is no longer valid.'**
  String get promoOutcomeRevoked;

  /// No description provided for @promoOutcomeRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a minute.'**
  String get promoOutcomeRateLimited;

  /// No description provided for @promoOutcomeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t apply the code. Try again.'**
  String get promoOutcomeUnknown;

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

  /// No description provided for @lockedBody.
  ///
  /// In en, this message translates to:
  /// **'Get a subscription or enter a promo code — then connect in one tap.'**
  String get lockedBody;

  /// No description provided for @lockedCta.
  ///
  /// In en, this message translates to:
  /// **'Get a subscription or enter a promo code'**
  String get lockedCta;

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

  /// No description provided for @settingsSupportHint.
  ///
  /// In en, this message translates to:
  /// **'Telegram — transfer after reinstall'**
  String get settingsSupportHint;

  /// No description provided for @lockedPay1m.
  ///
  /// In en, this message translates to:
  /// **'Pay 1 month'**
  String get lockedPay1m;

  /// No description provided for @lockedPay3m.
  ///
  /// In en, this message translates to:
  /// **'Pay 3 months'**
  String get lockedPay3m;

  /// No description provided for @lockedOrPromo.
  ///
  /// In en, this message translates to:
  /// **'Or enter a promo code'**
  String get lockedOrPromo;

  /// No description provided for @lockedPayFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t start payment. Try again or contact support.'**
  String get lockedPayFailed;

  /// No description provided for @lockedPayReturnTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment opened'**
  String get lockedPayReturnTitle;

  /// No description provided for @lockedPayReturnBody.
  ///
  /// In en, this message translates to:
  /// **'After you finish paying in the browser, tap Check access.'**
  String get lockedPayReturnBody;

  /// No description provided for @lockedPayReturnCheck.
  ///
  /// In en, this message translates to:
  /// **'Check access'**
  String get lockedPayReturnCheck;

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

  /// No description provided for @recoveryCodeBody.
  ///
  /// In en, this message translates to:
  /// **'Save this code — main way to restore after reinstall. Without it, contact support with Device ID and payment receipt.'**
  String get recoveryCodeBody;

  /// No description provided for @accountHubGuestLead.
  ///
  /// In en, this message translates to:
  /// **'You’re in guest mode. Link a contact so you don’t lose access.'**
  String get accountHubGuestLead;

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

  /// No description provided for @restoreBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the recovery code you saved at first unlock. Without it, contact support with Device ID and Platega receipt.'**
  String get restoreBody;

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

  /// No description provided for @restoreBodyCode.
  ///
  /// In en, this message translates to:
  /// **'After reinstall, enter the recovery code shown when you first opened the app.'**
  String get restoreBodyCode;

  /// No description provided for @settingsInviteDevice.
  ///
  /// In en, this message translates to:
  /// **'Invite another device'**
  String get settingsInviteDevice;

  /// No description provided for @settingsInviteDeviceHint.
  ///
  /// In en, this message translates to:
  /// **'Create a short seat code'**
  String get settingsInviteDeviceHint;

  /// No description provided for @settingsAcceptSeat.
  ///
  /// In en, this message translates to:
  /// **'Enter seat code'**
  String get settingsAcceptSeat;

  /// No description provided for @settingsAcceptSeatHint.
  ///
  /// In en, this message translates to:
  /// **'Join another account'**
  String get settingsAcceptSeatHint;

  /// No description provided for @settingsSeatCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Seat code'**
  String get settingsSeatCodeTitle;

  /// No description provided for @settingsSeatCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get settingsSeatCodeCopied;

  /// No description provided for @settingsSeatInviteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t create a seat code'**
  String get settingsSeatInviteFailed;

  /// No description provided for @settingsAcceptSeatOk.
  ///
  /// In en, this message translates to:
  /// **'Device joined the account'**
  String get settingsAcceptSeatOk;

  /// No description provided for @settingsSeatPremiumRequired.
  ///
  /// In en, this message translates to:
  /// **'Inviting devices requires Premium'**
  String get settingsSeatPremiumRequired;

  /// No description provided for @settingsSeatCodeNotFound.
  ///
  /// In en, this message translates to:
  /// **'Code not found or expired'**
  String get settingsSeatCodeNotFound;

  /// No description provided for @settingsSeatDeviceLimit.
  ///
  /// In en, this message translates to:
  /// **'Device limit reached for this account'**
  String get settingsSeatDeviceLimit;

  /// No description provided for @settingsSeatOwnCode.
  ///
  /// In en, this message translates to:
  /// **'You can’t accept your own code — enter it on another device'**
  String get settingsSeatOwnCode;

  /// No description provided for @settingsSeatAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t accept the seat code'**
  String get settingsSeatAcceptFailed;

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

  /// No description provided for @accountHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountHubTitle;

  /// No description provided for @accountHubLinkedLead.
  ///
  /// In en, this message translates to:
  /// **'Contact linked. Account details and access are below.'**
  String get accountHubLinkedLead;

  /// No description provided for @accountHubLinkTelegram.
  ///
  /// In en, this message translates to:
  /// **'Telegram'**
  String get accountHubLinkTelegram;

  /// No description provided for @accountHubLinkTelegramHint.
  ///
  /// In en, this message translates to:
  /// **'Link via the bot'**
  String get accountHubLinkTelegramHint;

  /// No description provided for @accountHubLinkEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountHubLinkEmail;

  /// No description provided for @accountHubLinkEmailHint.
  ///
  /// In en, this message translates to:
  /// **'Link with a code from email'**
  String get accountHubLinkEmailHint;

  /// No description provided for @accountHubRecovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get accountHubRecovery;

  /// No description provided for @accountHubRecoveryHint.
  ///
  /// In en, this message translates to:
  /// **'Restore access after reinstall'**
  String get accountHubRecoveryHint;

  /// No description provided for @accountHubRecoverySaveBanner.
  ///
  /// In en, this message translates to:
  /// **'Save your recovery code — you’ll need it after reinstall.'**
  String get accountHubRecoverySaveBanner;

  /// No description provided for @accountHubRecoverySaveCta.
  ///
  /// In en, this message translates to:
  /// **'Save code'**
  String get accountHubRecoverySaveCta;

  /// No description provided for @accountHubPromo.
  ///
  /// In en, this message translates to:
  /// **'Promo code'**
  String get accountHubPromo;

  /// No description provided for @accountHubPromoHint.
  ///
  /// In en, this message translates to:
  /// **'Redeem invite or beta access code'**
  String get accountHubPromoHint;

  /// No description provided for @accountHubAccessSection.
  ///
  /// In en, this message translates to:
  /// **'Your access'**
  String get accountHubAccessSection;

  /// No description provided for @accountHubContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get accountHubContact;

  /// No description provided for @accountHubLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load account'**
  String get accountHubLoadError;

  /// No description provided for @accountTelegramLead.
  ///
  /// In en, this message translates to:
  /// **'Open the bot and confirm. Come back — status updates automatically.'**
  String get accountTelegramLead;

  /// No description provided for @accountTelegramOpenBot.
  ///
  /// In en, this message translates to:
  /// **'Open Telegram'**
  String get accountTelegramOpenBot;

  /// No description provided for @accountTelegramWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmation…'**
  String get accountTelegramWaiting;

  /// No description provided for @accountTelegramWaitingHint.
  ///
  /// In en, this message translates to:
  /// **'After /start in the bot, return here.'**
  String get accountTelegramWaitingHint;

  /// No description provided for @accountTelegramStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t start Telegram linking'**
  String get accountTelegramStartFailed;

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

  /// No description provided for @vpnDisclosureTitle.
  ///
  /// In en, this message translates to:
  /// **'Protected connection'**
  String get vpnDisclosureTitle;

  /// No description provided for @vpnDisclosureLead.
  ///
  /// In en, this message translates to:
  /// **'Before the first connect, we explain how VPN works in Teremok and which data the service needs.'**
  String get vpnDisclosureLead;

  /// No description provided for @vpnDisclosureVpnTitle.
  ///
  /// In en, this message translates to:
  /// **'Why Android VPN is required'**
  String get vpnDisclosureVpnTitle;

  /// No description provided for @vpnDisclosureVpnBody.
  ///
  /// In en, this message translates to:
  /// **'The app uses the system VpnService to create a protected tunnel after you tap Connect. App traffic on the device is routed through this tunnel to Teremok VPN servers. This is the core function of the app — a protected connection, not access to a private corporate network.'**
  String get vpnDisclosureVpnBody;

  /// No description provided for @vpnDisclosureDataTitle.
  ///
  /// In en, this message translates to:
  /// **'What data we process'**
  String get vpnDisclosureDataTitle;

  /// No description provided for @vpnDisclosureDataBody.
  ///
  /// In en, this message translates to:
  /// **'Install ID (device ID) and account ID — to grant access and restore it after reinstall. Subscription purchase history (via the payment provider; we do not store card numbers). On your request — a diagnostic report from Settings. Aggregated usage summary (connect attempts, session length) — without browsing history.'**
  String get vpnDisclosureDataBody;

  /// No description provided for @vpnDisclosureNotTitle.
  ///
  /// In en, this message translates to:
  /// **'What we do not do'**
  String get vpnDisclosureNotTitle;

  /// No description provided for @vpnDisclosureNotBody.
  ///
  /// In en, this message translates to:
  /// **'We do not log visited websites and do not use an advertising ID. We do not monetize other apps’ traffic by manipulating ads.'**
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
