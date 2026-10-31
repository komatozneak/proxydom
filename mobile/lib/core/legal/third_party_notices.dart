import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter asset that [registerThirdPartyNotices] feeds to [LicenseRegistry].
const thirdPartyNoticesAsset = 'assets/legal/THIRD-PARTY-NOTICES.md';

bool _registered = false;

/// Registers the Go engine notices with [LicenseRegistry].
///
/// The asset is not read here. [LicenseRegistry] calls the closure only when
/// something listens to [LicenseRegistry.licenses], which is the license page.
/// A missing asset then fails that page and leaves startup alone: launch must
/// not wait on a file most people never open.
void registerThirdPartyNotices() {
  if (_registered) return;
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(thirdPartyNoticesAsset);
    yield LicenseEntryWithLineBreaks(const ['hy2bind'], text);
  });
  _registered = true;
}
