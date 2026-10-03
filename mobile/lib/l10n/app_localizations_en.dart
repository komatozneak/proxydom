// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Proxy Dom';

  @override
  String get loginTitle => 'Sign in';

  @override
  String get loginTestButton => 'Sign in (test button)';

  @override
  String get loginErrorTimeout => 'Server did not respond';

  @override
  String get loginErrorNetwork => 'No connection to server';

  @override
  String get loginErrorGeneric => 'Request failed';

  @override
  String get homeTitle => 'Proxy Dom';

  @override
  String get homeVpnHint => 'VPN UI — comes in step 9+';

  @override
  String get homeDisconnected => 'Not connected';

  @override
  String get homeConnecting => 'Connecting...';

  @override
  String get homeConnected => 'Connected';

  @override
  String get homeTapHint => 'Tap the house to connect';

  @override
  String get homeConnectingHint => 'Hold on — the house is opening the door…';

  @override
  String get homeConnectedHint => 'The house is online';

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
  String get navHome => 'Home';

  @override
  String get navVpn => 'VPN';

  @override
  String get navLocations => 'Locations';

  @override
  String get navModes => 'Modes';

  @override
  String get homeTrafficRemainder => 'Data left';

  @override
  String get homeTrafficExhausted => 'Traffic used up';

  @override
  String homeTrafficAmount(String remaining, String limit) {
    return '$remaining / $limit GB';
  }

  @override
  String get homeNoVpnRow => 'Allowlists';

  @override
  String get settingsNoVpn => 'Allowlists';

  @override
  String get settingsNoVpnHint => 'Apps and sites that go around';

  @override
  String get modesTitle => 'Mode';

  @override
  String get modesSubtitle => 'How VPN works';

  @override
  String get modeSmartTitle => 'Smart mode';

  @override
  String get modeSmartBody =>
      'Russian sites — direct, foreign sites — through VPN.';

  @override
  String get modeSmartBadge => 'AUTO';

  @override
  String get modeFullTitle => 'Full VPN';

  @override
  String get modeFullBody =>
      'All traffic goes through VPN. Simple and reliable.';

  @override
  String get modeSitesTitle => 'By site';

  @override
  String get modeSitesBody =>
      'Only selected sites go through VPN. Everything else is direct.';

  @override
  String get modesVpnOffTitle => 'VPN is off';

  @override
  String get modesVpnOffBody => 'Connect VPN so modes can take effect';

  @override
  String get modesConfirmFullTitle => 'Switch to Full VPN mode?';

  @override
  String get modesConfirmFullBody =>
      'In this mode all traffic goes through VPN. Russian services — Ozon, Wildberries, banks, Gosuslugi… may stop opening.\n\nTo keep them direct — use Smart mode.';

  @override
  String get modesConfirmFullCancel => 'Don\'t switch';

  @override
  String get modesConfirmFullOk => 'Switch';

  @override
  String get modesSitesSectionSmart => 'Also direct';

  @override
  String get modesSitesSectionSites => 'Sites through VPN';

  @override
  String get modesSitesCustomSection => 'Your sites';

  @override
  String get modesSitesCustomHint => 'e.g. twitch.tv';

  @override
  String get modesSitesAllowlistHint =>
      'Only selected sites go through VPN — everything else goes direct at full speed.';

  @override
  String get modesSitesMetaNote =>
      'Instagram and Facebook belong to Meta, recognized in Russia as an extremist organization and banned in the Russian Federation.';

  @override
  String get modesLocationTitle => 'Location';

  @override
  String get modesLocationHint => 'Server and country';

  @override
  String get modesPendingTitle => 'Reconnect VPN required';

  @override
  String get modesPendingBody => 'Routing changes apply after you reconnect.';

  @override
  String get modesReconnect => 'Reconnect';

  @override
  String get modesReconnectingTitle => 'Reconnecting VPN…';

  @override
  String get modesReconnectingBody => 'Applying routing changes';

  @override
  String get modesReconnectedTitle => 'Connected';

  @override
  String get modesReconnectFailedTitle => 'Reconnect failed';

  @override
  String get navSettings => 'Settings';

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
  String get homePathIncompatibleHint =>
      'Couldn’t reach a server. Tap again or pick a location yourself.';

  @override
  String get homeTtProvisionFailedTitle => 'Server unavailable';

  @override
  String get homeTtProvisionFailedHint =>
      'Couldn’t prepare this location. Try again later or pick another.';

  @override
  String get homeVpnProbeFailedTitle => 'Server not responding';

  @override
  String homeVpnProbeFailedHint(String node) {
    return 'Location $node is temporarily unavailable. Pick another in Locations or try again later.';
  }

  @override
  String get homeVpnConflictTitle => 'Another VPN is blocking';

  @override
  String get homeVpnConflictHint =>
      'Turn off the other VPN in Android settings, then connect again.';

  @override
  String get homeVpnConflictHintIos =>
      'Turn off the other VPN in Settings → VPN.';

  @override
  String homeVpnConflictHintNamed(String app) {
    return 'Turn off “$app” in Android settings, then connect again.';
  }

  @override
  String homeVpnConflictHintNamedIos(String app) {
    return 'Turn off “$app” in Settings → VPN.';
  }

  @override
  String get homeVpnPermissionHint =>
      'Allow the VPN in the Android system prompt, then tap connect again.';

  @override
  String get homeVpnPermissionHintIos =>
      'Allow VPN in the system prompt, then connect again.';

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
  String get settingsSubscription => 'Access';

  @override
  String get settingsSubscriptionActive => 'Active';

  @override
  String get settingsProBadge => 'PRO';

  @override
  String get settingsActiveBadge => 'Active';

  @override
  String get settingsAccessEarlySubtitle => 'Access is by invite.';

  @override
  String get settingsAccessBetaSubtitle =>
      'Invite access · Free limits lifted.';

  @override
  String get settingsAccessNoneTitle => 'No access';

  @override
  String get settingsAccessNoneSubtitle => 'An invite code is required.';

  @override
  String get settingsAccessFreeTitle => 'Free';

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
  String get settingsSubscriptionLoadError => 'Couldn’t load status';

  @override
  String get settingsServerRegion => 'Server region';

  @override
  String get settingsProtocol => 'Protocol';

  @override
  String get settingsProtocolLocked =>
      'Only VLESS + Reality is available for now';

  @override
  String get settingsKillSwitchOpenVpn => 'Open VPN settings';

  @override
  String get settingsKillSwitchOpenFailed =>
      'Couldn\'t open VPN settings. Open Settings → Network & internet → VPN.';

  @override
  String get settingsKillSwitchOpenFailedIos =>
      'Couldn\'t open VPN settings. Open Settings → VPN.';

  @override
  String get settingsDevices => 'Devices';

  @override
  String get settingsDevicesHint => 'Registered installs and revoke access';

  @override
  String get devicesTitle => 'Devices';

  @override
  String get devicesHint =>
      'You can log out other devices if you no longer have them.';

  @override
  String devicesCreated(String date) {
    return 'Created: $date';
  }

  @override
  String get devicesCurrentDevice => 'Current device';

  @override
  String get devicesSectionThis => 'This install';

  @override
  String get devicesSectionGroup => 'In the group';

  @override
  String get devicesSectionActions => 'Group';

  @override
  String get devicesInGroupLabel => 'In the group';

  @override
  String devicesGroupEmpty(int count) {
    return 'One device so far · $count slots left';
  }

  @override
  String get devicesLimitReached => 'Device limit reached';

  @override
  String devicesCount(int active, int max) {
    return '$active of $max';
  }

  @override
  String get devicesEmpty =>
      'No devices yet — connect VPN to register this one.';

  @override
  String get devicesLoadError => 'Could not load devices';

  @override
  String get devicesUntitled => 'Device';

  @override
  String get devicesRename => 'Rename';

  @override
  String get devicesRenameTitle => 'Device name';

  @override
  String get devicesRenameHint => 'Shown in the device list';

  @override
  String get devicesRenameSave => 'Save';

  @override
  String get devicesRenamed => 'Name updated';

  @override
  String get devicesRenameFailed => 'Could not rename device';

  @override
  String get devicesThisDevice => 'You';

  @override
  String get devicesInvitedLabel => 'Invited device';

  @override
  String get devicesRevoke => 'Remove';

  @override
  String get devicesRevokeTitle => 'Revoke this device?';

  @override
  String get devicesRevokeBody =>
      'This device\'s VPN key will stop working. Other devices are unaffected.';

  @override
  String get devicesRevokeConfirm => 'Revoke';

  @override
  String get devicesCancel => 'Cancel';

  @override
  String get devicesRevoked => 'Device revoked';

  @override
  String get devicesRevokeFailed => 'Could not revoke device';

  @override
  String get devicesLeaveHint => 'This install becomes its own Free account';

  @override
  String get devicesLeaveConfirm => 'Leave';

  @override
  String get devicesLeft => 'Device left the account';

  @override
  String get devicesLeaveFailed => 'Could not leave the account';

  @override
  String get devicesLogoutAll => 'Sign out everywhere';

  @override
  String get devicesLogoutAllHint =>
      'Revoke every device on this account, including this one';

  @override
  String get devicesLogoutAllTitle => 'Sign out on all devices?';

  @override
  String get devicesLogoutAllBody =>
      'Every device on this account will lose access, including this one. Recover with your code or register again.';

  @override
  String get devicesLogoutAllConfirm => 'Sign out everywhere';

  @override
  String get devicesLogoutAllFailed => 'Could not sign out everywhere';

  @override
  String get devicesLimitOpenManage => 'Manage devices';

  @override
  String get splitTunnelSearchHint => 'Search my sites';

  @override
  String get splitTunnelBundledSection => 'Ready-made list';

  @override
  String get splitTunnelBundledLead =>
      'Listed sites use your usual connection, not the protected one. Everything else still goes through Proxy Dom.';

  @override
  String get splitTunnelBundledRuTitle => 'Ready-made lists';

  @override
  String get splitTunnelBundledRuSubtitle =>
      'VK, Yandex, marketplaces, MAX, and more — one tap';

  @override
  String get splitTunnelBundledInfoTitle => 'How it works';

  @override
  String get splitTunnelBundledInfoBody =>
      'Listed sites use your usual connection, not the protected one. Everything else still goes through Proxy Dom.\n\nOn iPhone you cannot take a whole app out of the VPN — only a website by address. Safari usually follows the list. A bank or marketplace app may stay in the VPN.\n\nBig services use many servers. Some pages or video may still go through the VPN with the switch on. If a site should stay protected, turn it off here.\n\nTap Reconnect after you change the list.';

  @override
  String get splitTunnelBundledInfoClose => 'Got it';

  @override
  String get splitTunnelSitesLead =>
      'Listed sites use your usual connection, not the protected one. Everything else still goes through Proxy Dom.';

  @override
  String get splitTunnelSitesIosNote =>
      'On iPhone only exact hostnames leave the VPN (not all subdomains). Whole apps cannot leave the tunnel.';

  @override
  String get splitTunnelCustomSection => 'My sites';

  @override
  String splitTunnelCustomCount(int count) {
    return '$count';
  }

  @override
  String get splitTunnelAddSite => 'Add site';

  @override
  String get splitTunnelSiteNameOptional => 'Name (optional)';

  @override
  String get splitTunnelDomainLabel => 'Site address';

  @override
  String get splitTunnelDomainHint => 'example.com';

  @override
  String get splitTunnelSave => 'Add';

  @override
  String get splitTunnelCancel => 'Cancel';

  @override
  String get splitTunnelDelete => 'Delete';

  @override
  String get splitTunnelDeleteConfirm => 'Remove this site from the list?';

  @override
  String get splitTunnelEmptyTitle => 'No custom sites';

  @override
  String get splitTunnelEmptyBody =>
      'Add an exact hostname — only that address skips the VPN, not its subdomains.';

  @override
  String get splitTunnelInvalidDomain => 'Enter an address like example.com';

  @override
  String get splitTunnelDuplicateDomain =>
      'This address is already in the list';

  @override
  String get splitTunnelNonAsciiUnsupported => 'Latin addresses only';

  @override
  String get splitTunnelDomainLatinHelper => 'Latin addresses only';

  @override
  String get splitTunnelPendingTitle => 'Changes not applied yet';

  @override
  String get splitTunnelPendingBody => 'Changes apply after reconnecting';

  @override
  String get splitTunnelReconnect => 'Reconnect';

  @override
  String get splitTunnelReconnectInProgress => 'Reconnecting…';

  @override
  String get splitTunnelApplied => 'Rules applied';

  @override
  String get splitTunnelApplyFailed => 'Couldn\'t reconnect — try again';

  @override
  String get splitTunnelAppsLockdownWarning =>
      'Android “Block connections without VPN” is on. Apps in this list may have no internet until you turn that off or reconnect them through the VPN.';

  @override
  String get splitTunnelGeoHy2Pending =>
      'Not applied on this connection yet (needs IP lists). Use Apps or add a site.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsComingSoon => 'Coming soon — placeholder for now';

  @override
  String get settingsComingSoonBadge => 'Soon';

  @override
  String get settingsPrivacyPlaceholder => 'Privacy policy';

  @override
  String get settingsDarkTheme => 'Appearance';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsThemeSystem => 'Auto';

  @override
  String get settingsThemeDark => 'Dark';

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
  String get tunnelLogsTitle => 'Tunnel logs';

  @override
  String get tunnelLogsLevelOff => 'Off';

  @override
  String get tunnelLogsLevelError => 'Errors';

  @override
  String get tunnelLogsLevelWarn => 'Warnings';

  @override
  String get tunnelLogsLevelInfo => 'Info';

  @override
  String get tunnelLogsLevelDebug => 'Debug';

  @override
  String get tunnelLogsSearch => 'Text, IP, or domain';

  @override
  String get tunnelLogsAll => 'All';

  @override
  String get tunnelLogsSession => 'Session';

  @override
  String get tunnelLogsUi => 'Interface';

  @override
  String get tunnelLogsCore => 'Core';

  @override
  String get tunnelLogsDns => 'DNS';

  @override
  String get tunnelLogsFetch => 'Document';

  @override
  String get tunnelLogsNetwork => 'Network';

  @override
  String get tunnelLogsRefresh => 'Refresh';

  @override
  String get tunnelLogsCopy => 'Copy';

  @override
  String get tunnelLogsExport => 'Share';

  @override
  String get tunnelLogsDelete => 'Delete';

  @override
  String get tunnelLogsCopied => 'Log copied';

  @override
  String tunnelLogsDebugFile(String path) {
    return 'File to send: $path';
  }

  @override
  String get tunnelLogsEmpty => 'No entries';

  @override
  String get settingsSendReportHint =>
      'Copies diagnostics. Paste them into support yourself.';

  @override
  String get settingsSendReportConfirm => 'Send';

  @override
  String get settingsReportSent =>
      'Report sent to support via the bot. Also copied.';

  @override
  String get settingsReportCopied => 'Report text copied';

  @override
  String settingsReportSaved(String id) {
    return 'Report saved: $id. Copied to clipboard.';
  }

  @override
  String get settingsReportFailed => 'Couldn\'t build the report';

  @override
  String get settingsReportUnauthorized =>
      'Session expired — sign in again and retry';

  @override
  String get settingsReportNetworkError =>
      'Can\'t reach the server — try again later';

  @override
  String get settingsVpnNotificationTitle => 'Shade notification';

  @override
  String get settingsVpnNotificationHint =>
      'Card in the shade with Disconnect. Off hides the card; VPN stays on.';

  @override
  String get settingsQsTileTitle => 'Quick Settings tile';

  @override
  String get settingsQsTileHint =>
      'Add a tile to connect and disconnect from Quick Settings';

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
  String get settingsQsTileAddedHint =>
      'The tile is in Quick Settings. Tap to remove it';

  @override
  String get settingsQsTileRemove => 'Remove';

  @override
  String get settingsQsTileRemoveTitle => 'Remove the tile';

  @override
  String get settingsQsTileRemoveBody =>
      'Pull down the shade, tap the pencil, and drag “Proxy Dom” to the top.';

  @override
  String get settingsQsTileRemoveAck => 'Got it';

  @override
  String get settingsQsTileManual =>
      'Add manually: shade → pencil → “Proxy Dom”';

  @override
  String get settingsQsTileNotAdded => 'The tile was not added';

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
  String get regionAutoSubtitle => 'Nearest available location';

  @override
  String get regionSelected => 'Selected';

  @override
  String get regionSectionServers => 'Servers';

  @override
  String get regionSectionGeneral => 'General';

  @override
  String get regionSectionFree => 'Free';

  @override
  String get regionSectionEurope => 'Latvia';

  @override
  String get regionSectionUsa => 'USA';

  @override
  String get regionComingSoon => 'Coming soon';

  @override
  String get regionComingSoonBadge => 'Soon';

  @override
  String get regionSectionOffline => 'Unavailable servers';

  @override
  String get regionOnline => 'online';

  @override
  String get regionBlurbFree => 'Apps and websites';

  @override
  String get regionBlurbGaming => 'Low ping';

  @override
  String get regionBlurbYoutube => 'Comfortable streaming';

  @override
  String get regionBlurbIndia => 'Apps and websites';

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
  String get regionCachedHint =>
      'Showing a saved list — network is unstable right now';

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
  String get regionSwitchingTitle => 'Switching location…';

  @override
  String get regionSwitchingBody => 'Connecting to the selected server';

  @override
  String get regionSwitchedTitle => 'Done';

  @override
  String get regionSwitchFailedTitle => 'Could not switch location';

  @override
  String get logoutTooltip => 'Sign out';

  @override
  String get settingsDeviceId => 'Device ID';

  @override
  String get settingsDeviceIdCopied => 'Device ID copied';

  @override
  String get settingsDeviceIdHint => 'Install identifier for support';

  @override
  String get logoutConfirmTitle => 'Sign out?';

  @override
  String get logoutConfirmMessage =>
      'Your VPN connection will be closed. Restore with your code or register again next time.';

  @override
  String get logoutWarning => 'Logout completed with warnings';

  @override
  String get cancel => 'Cancel';

  @override
  String get navBack => 'Back';

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

  @override
  String get welcomeHeadline => 'A warm house on a cold internet';

  @override
  String get welcomeBody =>
      'An account is created automatically. Then one tap for a protected connection.';

  @override
  String get welcomeContinue => 'Continue';

  @override
  String get welcomeSkip => 'Skip';

  @override
  String get referralShareTitle => 'Invite a friend';

  @override
  String get referralShareBody =>
      'They enter your code after install. Extra days land after they pay, not after install.';

  @override
  String get referralCopy => 'Copy link';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingDone => 'Get started';

  @override
  String get onboardingConnectTitle => 'Connect';

  @override
  String get onboardingConnectBody =>
      'Tap Connect on Home. Android will ask for VPN permission once — that’s normal.';

  @override
  String get onboardingConnectBodyIos =>
      'Tap Connect on Home. iPhone will ask for VPN permission once — that’s normal.';

  @override
  String get onboardingRegionTitle => 'Region';

  @override
  String get onboardingRegionBody =>
      'Automatic region is recommended. You can change it later in the list.';

  @override
  String get onboardingHelpTitle => 'Help and privacy';

  @override
  String get onboardingHelpBody =>
      'Send a diagnostic report from Settings if something breaks. We only collect a minimal daily aggregate — no browsing history, apps list, or ad IDs.';

  @override
  String get betaGateError => 'Couldn’t check access. Check your connection.';

  @override
  String get betaGateChecking => 'Checking access…';

  @override
  String get betaGateErrorTimeout =>
      'The server did not respond. If VPN is on, turn it off and retry.';

  @override
  String get betaGateErrorUnauthorized => 'Session expired. Try again.';

  @override
  String get betaGateDisconnectVpnRetry => 'Disconnect VPN and retry';

  @override
  String get betaGateContinueAnyway => 'Continue anyway';

  @override
  String get lockedTitle => 'Activation';

  @override
  String get lockedHeadline => 'Welcome!';

  @override
  String get lockedRefreshAccess => 'Refresh access';

  @override
  String get settingsSupport => 'Support';

  @override
  String get lockedPlan1m => '1 month';

  @override
  String get lockedPlan3m => '3 months';

  @override
  String get lockedPlan6m => '6 months';

  @override
  String get lockedPlan12m => '12 months';

  @override
  String lockedSavePercent(int percent) {
    return '−$percent%';
  }

  @override
  String lockedVerifyCode(String code) {
    return 'Verification code: $code';
  }

  @override
  String get settingsTerms => 'Agreement';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get recoveryCodeTitle => 'Recovery code';

  @override
  String get recoveryCodeHeadline => 'Recovery code';

  @override
  String get recoveryCodeCopy => 'Copy code';

  @override
  String get recoveryCodeCopied => 'Code copied';

  @override
  String get recoveryCodeConfirm => 'Continue';

  @override
  String get recoveryCodeContinue => 'Continue';

  @override
  String get restoreTitle => 'Restore access';

  @override
  String get restoreHeadline => 'Enter recovery code';

  @override
  String get restorePaymentLabel => 'Payment ID';

  @override
  String get restorePaymentHint => 'UUID from the payment receipt';

  @override
  String get restorePaymentEmpty => 'Enter the payment ID';

  @override
  String get restorePaymentNotFound => 'Payment not found. Check the ID.';

  @override
  String get restorePaymentNotConfirmed => 'This payment is not confirmed yet.';

  @override
  String get restoreCodeLabel => 'Recovery code';

  @override
  String get restoreCodeHint => 'TRM-XXXX-XXXX-XXXX';

  @override
  String get restoreCodeEmpty => 'Enter your recovery code';

  @override
  String get restoreSubmit => 'Restore';

  @override
  String get restoreInvalid => 'Invalid recovery code';

  @override
  String get restoreFailed => 'Couldn’t restore access. Try again.';

  @override
  String get restoreDeviceLimitTitle => 'Device limit reached';

  @override
  String get restoreDeviceLimitBody =>
      'Choose which device to disconnect so this device can join.';

  @override
  String get restoreAccountFull =>
      'Device limit reached. Remove one in the device list, then sign in again. Devices already signed in stay online.';

  @override
  String get restoreDeviceLimitOwner => 'Owner';

  @override
  String get restoreDeviceLimitPickFailed =>
      'Couldn’t free a device slot. Try again.';

  @override
  String get restoreSettingsHint =>
      'After reinstall — enter your recovery code';

  @override
  String get restoreHeadlineCode => 'Enter recovery code';

  @override
  String get settingsInviteDeviceHint => 'Create a code to join your group';

  @override
  String get settingsAcceptSeat => 'Join group';

  @override
  String get settingsAcceptSeatHint => 'Join a subscription by invitation';

  @override
  String get settingsSeatCodeTitle => 'Invitation code';

  @override
  String get settingsSeatCodeCopied => 'Code copied';

  @override
  String get settingsSeatInviteFailed => 'Couldn’t create an invitation code';

  @override
  String get settingsAcceptSeatOk => 'Device added to the group';

  @override
  String get settingsSeatCodeNotFound => 'Code not found or expired';

  @override
  String get settingsSeatOwnCode =>
      'You can’t accept your own code — enter it on another device';

  @override
  String get settingsSeatAcceptFailed => 'Couldn’t join the group';

  @override
  String get settingsSeatCodeTtl => 'Code is valid for 30 minutes';

  @override
  String get settingsSeatShowQr => 'Show code';

  @override
  String get settingsSeatScanHint => 'Scan the QR code or follow the link';

  @override
  String get seatAcceptConsentTitle => 'Join this group?';

  @override
  String get seatAcceptConsentBody =>
      'The account owner will see this device’s name, platform, and the date it was added. You can leave the group later.';

  @override
  String get seatAcceptConsentConfirm => 'Join';

  @override
  String get devicesOwnerCannotLeave => 'Revoke other devices before leaving';

  @override
  String get settingsRecoverAccess => 'Restore access';

  @override
  String get settingsRecoverAccessHint => 'Use recovery code after reinstall';

  @override
  String get bootstrapFailed =>
      'Couldn’t start the session. Check your connection.';

  @override
  String get accountEmailLead =>
      'Enter your email — we’ll send a one-time code.';

  @override
  String get accountEmailLabel => 'Email';

  @override
  String get accountEmailSendCode => 'Send code';

  @override
  String get accountEmailCodeLabel => 'Code from email';

  @override
  String get accountEmailVerify => 'Confirm';

  @override
  String get accountEmailChangeAddress => 'Different address';

  @override
  String get accountEmailInvalid => 'Enter a valid email';

  @override
  String get accountEmailSendFailed => 'Couldn’t send the code';

  @override
  String get accountEmailCodeRequired => 'Enter the code from email';

  @override
  String get accountEmailVerifyFailed => 'Invalid or expired code';

  @override
  String get accountEmailDebugHint => 'DEBUG: code filled from API response';

  @override
  String get navPromo => 'Invite code';

  @override
  String get iosBillingUnavailableBody =>
      'In-app payment is not available. Free locations still work.';

  @override
  String get iosAdvancedFeaturesCta => 'Advanced features';

  @override
  String get vpnDisclosureTitle => 'How the tunnel starts';

  @override
  String get vpnDisclosureLead =>
      'The house starts a tunnel from the line you chose. This screen explains that before Android asks for VPN permission.';

  @override
  String get vpnDisclosureVpnTitle => 'What the app does';

  @override
  String get vpnDisclosureVpnBody =>
      'After you accept, the house opens a local tunnel for the selected line. Device traffic goes to the server in that line. Android then shows its own VPN permission once.';

  @override
  String get vpnDisclosureVpnTitleIos => 'What the app does';

  @override
  String get vpnDisclosureVpnBodyIos =>
      'After you accept, the house opens a local tunnel for the selected line. Device traffic goes to the server in that line. iPhone then shows its own VPN permission once.';

  @override
  String get vpnDisclosureDataTitle => 'What stays on the phone';

  @override
  String get vpnDisclosureDataBody =>
      'The access line stays on the device. A diagnostic report leaves the phone only if you send it from Settings. Browsing history is not recorded.';

  @override
  String get vpnDisclosureDataBodyIos =>
      'The access line stays on the device. A diagnostic report leaves the phone only if you send it from Settings. Browsing history is not recorded.';

  @override
  String get vpnDisclosureNotTitle => 'What the app does not do';

  @override
  String get vpnDisclosureNotBody =>
      'It does not keep a history of sites and it does not read an advertising ID. It does not sell access or hand out servers: you bring the line.';

  @override
  String get vpnDisclosureAccept => 'Accept and continue';

  @override
  String get vpnDisclosureDecline => 'Not now';

  @override
  String get freeAdd => 'Add';

  @override
  String get freePaste => 'Paste';

  @override
  String get freeQr => 'QR';

  @override
  String get freeAddServer => 'Add server';

  @override
  String get freeEmptyTitle => 'No servers added';

  @override
  String get freeEmptyBody => 'Add a link, a key, or a QR code.';

  @override
  String get freeStatus => 'Status';

  @override
  String get freeProfile => 'Profile';

  @override
  String get freeProtocol => 'Protocol';

  @override
  String get freeTrafficLeft => 'Remaining';

  @override
  String get freeUptime => 'Uptime';

  @override
  String get freeNoProfile => 'None';

  @override
  String get freeAddTitle => 'Add';

  @override
  String get freeAddHint => 'Paste a link or a key.';

  @override
  String get freeSaveConnect => 'Save';

  @override
  String get freeSaveOnly => 'Save only';

  @override
  String get freePreview => 'Found';

  @override
  String get freeServerAdded => 'Server added';

  @override
  String get freeLinkInvalid => 'Could not read that link';

  @override
  String get freeSubscriptionLoadFail =>
      'The document did not load. The host did not answer.';

  @override
  String get freeSubscriptionMissing => 'That address has no document.';

  @override
  String get freeSubscriptionDeviceLimit =>
      'This document has no free device slots. Free one and refresh the list.';

  @override
  String get freeSubscriptionClientRefused =>
      'The document sent a placeholder instead of a server.';

  @override
  String get freeSharePool => 'Share';

  @override
  String get freeShareCopied => 'Key copied';

  @override
  String get freeShareFail => 'Could not create the link';

  @override
  String get freeOnboardTitle => 'Server list';

  @override
  String get freeOnboardBody =>
      'An address or a key becomes a profile. Its servers stay in one list.';

  @override
  String get freeOnboardAddTitle => 'Pick a server';

  @override
  String get freeOnboardAddBody =>
      'Each server has a name and a short line. You choose which one to use.';

  @override
  String get freeOnboardConnectTitle => 'Connect with one tap';

  @override
  String get freeOnboardConnectBody =>
      'Tap the house to connect or disconnect. The status stays on this screen.';

  @override
  String get freeLater => 'Later';

  @override
  String get freeBatteryTitle => 'Keep the tunnel running';

  @override
  String get freeBatteryBody =>
      'Android may stop the tunnel to save battery. You can allow background activity.';

  @override
  String get freeBatteryAllow => 'Allow';

  @override
  String get freeBatteryDismiss => 'Don\'t ask again';

  @override
  String get freeServers => 'Servers';

  @override
  String get freePoolMarked => 'Marked';

  @override
  String get freeIosHy2Only => 'This protocol cannot start.';

  @override
  String get freeHy2OnlyAdd =>
      'Could not add the node: only Hysteria2 is supported.';

  @override
  String get freeNoHy2Lines => 'This source has no Hysteria2 lines.';

  @override
  String get freeSchemeParked => 'This protocol cannot start.';

  @override
  String get freePoolGeneral => 'General';

  @override
  String get freeSearch => 'Search servers';

  @override
  String get freeDelete => 'Remove';

  @override
  String get freeDeleteServerTitle => 'Remove this server?';

  @override
  String get freeDeleteServerBody => 'The link is deleted from this phone.';

  @override
  String get freeDeleteCatalogTitle => 'Remove this list?';

  @override
  String get freeDeleteCatalogBody =>
      'Every server in the list is deleted from this phone.';

  @override
  String get freeRefresh => 'Refresh';

  @override
  String freeRefreshDone(int count) {
    return 'Updated: $count';
  }

  @override
  String get freeRefreshFail => 'Could not refresh';
}
