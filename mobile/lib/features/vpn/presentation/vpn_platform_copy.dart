import 'package:flutter/foundation.dart';

import '../../../l10n/app_localizations.dart';

bool get isIosTargetPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

String homeVpnConflictHintForPlatform(AppL10n l) =>
    isIosTargetPlatform ? l.homeVpnConflictHintIos : l.homeVpnConflictHint;

String homeVpnConflictHintNamedForPlatform(AppL10n l, String app) =>
    isIosTargetPlatform
        ? l.homeVpnConflictHintNamedIos(app)
        : l.homeVpnConflictHintNamed(app);

String homeVpnPermissionHintForPlatform(AppL10n l) =>
    isIosTargetPlatform ? l.homeVpnPermissionHintIos : l.homeVpnPermissionHint;

String settingsKillSwitchOpenFailedForPlatform(AppL10n l) => isIosTargetPlatform
    ? l.settingsKillSwitchOpenFailedIos
    : l.settingsKillSwitchOpenFailed;

String vpnDisclosureVpnTitleForPlatform(AppL10n l) =>
    isIosTargetPlatform ? l.vpnDisclosureVpnTitleIos : l.vpnDisclosureVpnTitle;

String vpnDisclosureVpnBodyForPlatform(AppL10n l) =>
    isIosTargetPlatform ? l.vpnDisclosureVpnBodyIos : l.vpnDisclosureVpnBody;

String vpnDisclosureDataBodyForPlatform(AppL10n l) =>
    isIosTargetPlatform ? l.vpnDisclosureDataBodyIos : l.vpnDisclosureDataBody;

String regionSectionYoutubeForPlatform(AppL10n l) =>
    isIosTargetPlatform ? l.regionSectionYoutubeIos : l.regionSectionYoutube;

String settingsSupportHintForPlatform(AppL10n l) =>
    isIosTargetPlatform ? l.settingsSupportHintIos : l.settingsSupportHint;

String accountHubLinkedLeadForPlatform(AppL10n l) =>
    isIosTargetPlatform ? l.accountHubLinkedLeadIos : l.accountHubLinkedLead;

String restoreBodyForPlatform(AppL10n l) =>
    isIosTargetPlatform ? l.restoreBodyIos : l.restoreBody;

String restoreBodyCodeForPlatform(AppL10n l) =>
    isIosTargetPlatform ? l.restoreBodyCodeIos : l.restoreBodyCode;

/// Strings Home / gate / disclosure actually paint for the current platform.
List<String> visibleVpnGuidanceCopy(AppL10n l) => [
      homeVpnConflictHintForPlatform(l),
      homeVpnConflictHintNamedForPlatform(l, 'OtherVPN'),
      homeVpnPermissionHintForPlatform(l),
      settingsKillSwitchOpenFailedForPlatform(l),
      vpnDisclosureVpnTitleForPlatform(l),
      vpnDisclosureVpnBodyForPlatform(l),
      vpnDisclosureDataBodyForPlatform(l),
    ];
