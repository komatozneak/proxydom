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
  String get homeVpnHint => 'Tunnel status — comes in step 9+';

  @override
  String get homeDisconnected => 'Not connected';

  @override
  String get homeConnecting => 'Connecting...';

  @override
  String get homeConnected => 'Connected';

  @override
  String get homeTapHint => 'Tap to connect';

  @override
  String get homeConnectingHint => 'Connecting…';

  @override
  String get homeConnectedHint => 'Connected';

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
  String get navVpn => 'Tunnel';

  @override
  String get navLocations => 'Locations';

  @override
  String get navModes => 'Modes';

  @override
  String get homeTrafficRemainder => 'Data left';

  @override
  String get homeTrafficExhausted => 'Traffic used up';

  @override
  String get homeTrafficLabel => 'TRAFFIC';

  @override
  String get homeAddServer => 'Add server';

  @override
  String get homeMetricTime => 'Time';

  @override
  String get homeMetricSpeed => 'Speed';

  @override
  String get homeMetricTraffic => 'Traffic';

  @override
  String get homeTrafficUnlimited => 'UNLIMITED';

  @override
  String get profileTrafficRemaining => 'remaining';

  @override
  String get profileTrafficUsed => 'used';

  @override
  String get profileTrafficNoData => 'no limit data';

  @override
  String get profileTrafficStale => 'stale';

  @override
  String get profileTrafficExpires => 'expires';

  @override
  String get profileSourceLocal => 'local import';

  @override
  String homeTrafficAmount(String remaining, String limit) {
    return '$remaining / $limit GB';
  }

  @override
  String get homeNoVpnRow => 'Routing';

  @override
  String get settingsNoVpn => 'Routing';

  @override
  String get settingsNoVpnHint => 'Split-tunnel rules for apps and sites';

  @override
  String get modesTitle => 'Mode';

  @override
  String get modesSubtitle => 'How the tunnel works';

  @override
  String get modeSmartTitle => 'Smart mode';

  @override
  String get modeSmartBody =>
      'Russian corporate resources stay direct; everything else goes through the selected node.';

  @override
  String get modeSmartBadge => 'AUTO';

  @override
  String get modeFullTitle => 'Full tunnel';

  @override
  String get modeFullBody =>
      'All traffic goes through the selected node. Simple and predictable.';

  @override
  String get modeSitesTitle => 'By site';

  @override
  String get modeSitesBody =>
      'Only selected sites go through the tunnel. Everything else is direct.';

  @override
  String get modesVpnOffTitle => 'Tunnel is off';

  @override
  String get modesVpnOffBody => 'Connect the tunnel so modes can take effect';

  @override
  String get modesConfirmFullTitle => 'Switch to Full tunnel mode?';

  @override
  String get modesConfirmFullBody =>
      'In this mode all traffic goes through the selected node. Internal services and Russian resources may become slower.\n\nTo keep them direct — use Smart mode.';

  @override
  String get modesConfirmFullCancel => 'Don\'t switch';

  @override
  String get modesConfirmFullOk => 'Switch';

  @override
  String get modesSitesSectionSmart => 'Also direct';

  @override
  String get modesSitesSectionSites => 'Sites through the tunnel';

  @override
  String get modesSitesCustomSection => 'Your sites';

  @override
  String get modesSitesCustomHint => 'gw.company-net.ru';

  @override
  String get modesSitesAllowlistHint =>
      'Only selected sites go through the tunnel — everything else goes direct at full speed.';

  @override
  String get modesLocationTitle => 'Location';

  @override
  String get modesLocationHint => 'Server and country';

  @override
  String get modesPendingTitle => 'Tunnel restart required';

  @override
  String get modesPendingBody => 'Routing changes apply after you reconnect.';

  @override
  String get modesReconnect => 'Reconnect';

  @override
  String get modesReconnectingTitle => 'Reconnecting the tunnel…';

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
  String get homeStatPingPending => 'measuring';

  @override
  String get homeLinkOnline => 'Connected';

  @override
  String get homeLinkOffline => 'Home offline';

  @override
  String get homeLinkLabel => 'Link';

  @override
  String get homeStatDownload => 'Download';

  @override
  String get homeStatUpload => 'Upload';

  @override
  String get homeMoreMenu => 'More';

  @override
  String get homeRetry => 'Retry';

  @override
  String get homeErrorFriendly => 'Couldn’t connect. Please try again.';

  @override
  String get homeNodeAuthRefused =>
      'The node refused authentication. The session is not allowed: this period’s traffic is used up, or the key was revoked.';

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
  String get homeVpnConflictTitle => 'Another tunnel is blocking';

  @override
  String get homeVpnConflictHint =>
      'Turn off the other tunnel in Android settings, then connect again.';

  @override
  String get homeVpnConflictHintIos =>
      'Turn off the other tunnel in Settings → VPN.';

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
      'Allow the tunnel in the Android system prompt, then tap connect again.';

  @override
  String get homeVpnPermissionHintIos =>
      'Allow the tunnel in the system prompt, then connect again.';

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
  String get settingsProBadge => 'PRO';

  @override
  String get settingsActiveBadge => 'Active';

  @override
  String get settingsServerRegion => 'Server region';

  @override
  String get settingsProtocol => 'Protocol';

  @override
  String get settingsProtocolLocked =>
      'Only VLESS + Reality is available for now';

  @override
  String get settingsKillSwitchOpenVpn => 'Open tunnel settings';

  @override
  String get settingsKillSwitchOpenFailed =>
      'Couldn\'t open tunnel settings. Open Settings → Network & internet → VPN.';

  @override
  String get settingsKillSwitchOpenFailedIos =>
      'Couldn\'t open tunnel settings. Open Settings → VPN.';

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
      'No devices yet — connect the tunnel to register this one.';

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
      'This device\'s tunnel key will stop working. Other devices are unaffected.';

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
      'Listed sites use your usual connection, not the protected one. Everything else still goes through Proxy Dom.\n\nOn iPhone you cannot take a whole app out of the tunnel — only a website by address. Safari usually follows the list. A bank or marketplace app may stay in the tunnel.\n\nBig services use many servers. Some pages or video may still go through the tunnel with the switch on. If a site should stay protected, turn it off here.\n\nTap Reconnect after you change the list.';

  @override
  String get splitTunnelBundledInfoClose => 'Got it';

  @override
  String get splitTunnelSitesLead =>
      'Listed sites use your usual connection, not the protected one. Everything else still goes through Proxy Dom.';

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
  String get splitTunnelDomainHint => 'gw.company-net.ru';

  @override
  String get splitTunnelSave => 'Add';

  @override
  String get splitTunnelCancel => 'Cancel';

  @override
  String get splitTunnelDelete => 'Delete';

  @override
  String get splitTunnelDeleteConfirm => 'Remove this site from the list?';

  @override
  String get splitTunnelEdit => 'Edit';

  @override
  String get splitTunnelEditDone => 'Done';

  @override
  String splitTunnelPlayersFound(int count) {
    return 'Players found: $count';
  }

  @override
  String splitTunnelPlayersCount(int count) {
    return 'Players: $count';
  }

  @override
  String get splitTunnelEmptyTitle => 'No custom sites';

  @override
  String get splitTunnelEmptyBody =>
      'Add an exact hostname — only that address skips the tunnel, not its subdomains.';

  @override
  String get splitTunnelInvalidDomain =>
      'Enter an address like gw.company-net.ru';

  @override
  String get splitTunnelDuplicateDomain =>
      'This address is already in the list';

  @override
  String get splitTunnelNonAsciiUnsupported => 'Latin addresses only';

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
      'Android lockdown mode is on. Apps in this list may have no internet until you turn it off or return them to the tunnel.';

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
  String get settingsLicensesHint =>
      'Licenses of the engine and the libraries it links';

  @override
  String get licensesTitle => 'Open Source Notices';

  @override
  String get licensesSearch => 'Search packages';

  @override
  String get licensesEngine => 'Engine';

  @override
  String get licensesPackages => 'Packages';

  @override
  String get licensesFonts => 'Fonts';

  @override
  String get licensesNoResults => 'Nothing found';

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
  String tunnelLogsClearBlocked(String files) {
    return 'Could not delete: $files. Administrator rights are required.';
  }

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
  String get settingsVpnNotificationShort => 'Shade card with Disconnect';

  @override
  String get settingsVpnNotificationHint =>
      'Card in the shade with Disconnect. Off hides the card; the tunnel stays on.';

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
  String get settingsQsTileAddedHint => 'Tap to remove';

  @override
  String get settingsQsTileRemove => 'Remove';

  @override
  String get settingsQsTileRemoveTitle => 'Remove the tile';

  @override
  String get settingsQsTileRemoveBody =>
      'Pull down the shade, tap the pencil, and drag the “Proxy Dom” tile to the trash.';

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
  String get regionSectionEurope => 'Moscow';

  @override
  String get regionSectionUsa => 'St Petersburg';

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
      'Cannot reach API — turn off the system Always-on mode (and lockdown), then reopen the region list';

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
      'Your tunnel connection will be closed. Restore with your code or register again next time.';

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
      'Tap Connect on Home. Android will ask for tunnel permission once — that’s normal.';

  @override
  String get onboardingConnectBodyIos =>
      'Tap Connect on Home. iPhone will ask for tunnel permission once — that’s normal.';

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
      'The server did not respond. If the tunnel is on, turn it off and retry.';

  @override
  String get betaGateErrorUnauthorized => 'Session expired. Try again.';

  @override
  String get betaGateDisconnectVpnRetry => 'Disconnect the tunnel and retry';

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
  String get vpnDisclosureBullet1 =>
      'The tunnel starts only on your command and only on this device.';

  @override
  String get vpnDisclosureBullet2 =>
      'Keys and node addresses are never sent to a server.';

  @override
  String get vpnDisclosureBullet3 => 'No account, no payments, no ads.';

  @override
  String get vpnDisclosureMore => 'Details';

  @override
  String get vpnDisclosureClose => 'Close';

  @override
  String get vpnDisclosureLead =>
      'The app starts a tunnel for the selected line. Android will ask for tunnel permission once.';

  @override
  String get vpnDisclosureVpnTitle => 'What the app does';

  @override
  String get vpnDisclosureVpnBody =>
      'After you agree, the app brings up a local tunnel for the selected line. Traffic goes to the server in that line. Android asks for tunnel permission once.';

  @override
  String get vpnDisclosureVpnTitleIos => 'What the app does';

  @override
  String get vpnDisclosureVpnBodyIos =>
      'After you agree, the app brings up a local tunnel for the selected line. Traffic goes to the server in that line. iPhone asks for tunnel permission once.';

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
  String freeImportCount(int recognized, int unsupported) {
    return 'Read $recognized, unsupported $unsupported';
  }

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
      'An address or a key becomes a profile. Its nodes stay in one list: Moscow (Primary), St Petersburg (Backup), Novosibirsk (Low ping).';

  @override
  String get freeOnboardAddTitle => 'Pick a server';

  @override
  String get freeOnboardAddBody =>
      'Each server has a name and a short line. You choose which one to use.';

  @override
  String get freeOnboardConnectTitle => 'Connect with one tap';

  @override
  String get freeOnboardConnectBody =>
      'Tap the connect button in the centre of the screen. It turns the tunnel on and off. The status stays on this screen.';

  @override
  String get pcOnboardHeadline => 'Connect on this PC';

  @override
  String get pcOnboardBody =>
      'Paste an access key or a document link. The app will show the nodes it contains, for example gw.company-net.ru.';

  @override
  String get pcOnboardPrivacy =>
      'Keys and server addresses stay on this computer.';

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
      'Could not add the node: this protocol cannot start on this device.';

  @override
  String get freeNoHy2Lines => 'This source has no lines the client can start.';

  @override
  String get freeSchemeParked => 'This protocol cannot start.';

  @override
  String get freePoolGeneral => 'General';

  @override
  String get freeSearch => 'Search servers';

  @override
  String get freeSearchEmpty => 'No servers found';

  @override
  String get qrHint => 'Point the camera at the QR code';

  @override
  String get qrTorch => 'Torch';

  @override
  String get locationsNodes => 'Nodes';

  @override
  String get locationsSelected => 'IN USE';

  @override
  String get locationsActive => 'Active';

  @override
  String get locationsNotUsed => 'NOT USED';

  @override
  String get locationsUseIt => 'Connect';

  @override
  String get locationsInUse => 'Connected';

  @override
  String get locationsShareKey => 'Key';

  @override
  String get freeTelegram => 'Telegram';

  @override
  String get locationsKeyHandle => 'key';

  @override
  String get freeDelete => 'Remove';

  @override
  String get freeDeleteServerTitle => 'Remove this server?';

  @override
  String get freeDeleteServerBody => 'The link is deleted from this device.';

  @override
  String get freeDeleteCatalogTitle => 'Remove this list?';

  @override
  String get freeDeleteCatalogBody =>
      'Every server in the list is deleted from this device.';

  @override
  String get freeRefresh => 'Refresh';

  @override
  String freeRefreshDone(int count) {
    return 'Updated: $count';
  }

  @override
  String get freeRefreshFail => 'Could not refresh';

  @override
  String get freeStepLink => 'Link';

  @override
  String get freeStepFound => 'Found';

  @override
  String get freeFoundEmpty =>
      'Nodes from the link will appear here — for example Moscow (Primary) or St Petersburg (Backup).';

  @override
  String get freeFieldEmpty =>
      'Empty for now. Paste a link and we will see what is inside.';
}
