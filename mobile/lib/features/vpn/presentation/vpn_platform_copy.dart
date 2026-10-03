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
