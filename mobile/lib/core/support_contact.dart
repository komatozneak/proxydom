import 'package:url_launcher/url_launcher.dart';

import 'config.dart';

/// Opens the public support page. The page lists a reply address.
class SupportContact {
  SupportContact._();

  static Future<bool> open() {
    return launchUrl(supportPageUri(), mode: LaunchMode.externalApplication);
  }

  static Uri supportPageUri() => Uri.parse(AppConfig.supportPageUrl);
}
