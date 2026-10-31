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
  String get homeDisconnected => 'Not connected';

  @override
  String get homeConnecting => 'Connecting...';

  @override
  String get homeConnected => 'Connected';

  @override
  String get homeError => 'Connection failed';

  @override
  String get homeConnect => 'Connect';

  @override
  String get homeRegion => 'Region';

  @override
  String get navHome => 'Home';

  @override
  String get navVpn => 'Tunnel';

  @override
  String get homeTrafficExhausted => 'Traffic used up';

  @override
  String get homeTrafficLabel => 'TRAFFIC';

  @override
  String get homeAddServer => 'Add server';

  @override
  String get homeMetricTime => 'Time';

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
  String get homeNoVpnRow => 'Routing';

  @override
  String get settingsNoVpn => 'Routing';

  @override
  String get settingsNoVpnHint => 'Split-tunnel rules for apps and sites';

  @override
  String get navSettings => 'Settings';

  @override
  String get homeStatServer => 'Server';

  @override
  String get homeStatPing => 'Ping';

  @override
  String get homeStatPingPending => 'measuring';

  @override
  String get homeErrorFriendly => 'Couldn’t connect. Please try again.';

  @override
  String get homeNodeAuthRefused =>
      'The node refused authentication. The session is not allowed: this period’s traffic is used up, or the key was revoked.';

  @override
  String get homePathIncompatibleHint =>
      'Couldn’t reach a server. Tap again or pick a location yourself.';

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
  String get settingsSectionConnection => 'Connection';

  @override
  String get settingsSectionApp => 'Application';

  @override
  String get settingsKillSwitchOpenVpn => 'Open tunnel settings';

  @override
  String get settingsKillSwitchOpenFailed =>
      'Couldn\'t open tunnel settings. Open Settings → Network & internet → VPN.';

  @override
  String get settingsKillSwitchOpenFailedIos =>
      'Couldn\'t open tunnel settings. Open Settings → VPN.';

  @override
  String get splitTunnelSitesLead =>
      'Listed sites use your usual connection, not the protected one. Everything else still goes through Proxy Dom.';

  @override
  String get splitTunnelCustomSection => 'My sites';

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
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsPrivacyPlaceholder => 'Privacy policy';

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
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsTitle => 'Settings';

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
  String get settingsQsTileAdded => 'Tile added to Quick Settings';

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
  String get homeSessionLabel => 'Session';

  @override
  String get regionAutoTitle => 'Automatic';

  @override
  String get regionAutoSubtitle => 'Nearest available location';

  @override
  String get cancel => 'Cancel';

  @override
  String get navBack => 'Back';

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
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingConnectBody =>
      'Tap Connect on Home. Android will ask for tunnel permission once — that’s normal.';

  @override
  String get onboardingConnectBodyIos =>
      'Tap Connect on Home. iPhone will ask for tunnel permission once — that’s normal.';

  @override
  String get settingsSupport => 'Support';

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
  String get freeHy2OnlyAdd =>
      'Could not add the node: this protocol cannot start on this device.';

  @override
  String get freeNoHy2Lines => 'This source has no lines the client can start.';

  @override
  String get freeSchemeParked => 'This protocol cannot start.';

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
  String get locationsActive => 'Active';

  @override
  String get locationsShareKey => 'Key';

  @override
  String get freeTelegram => 'Telegram';

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
