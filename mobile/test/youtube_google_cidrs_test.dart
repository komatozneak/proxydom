import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/youtube_google_cidrs.dart';

void main() {
  test('parseYoutubeGoogleCidrs skips comments and blanks', () {
    const raw = '''
# header
# sync-token: 1

8.8.8.0/24
104.154.0.0/15

# trailing
''';
    expect(parseYoutubeGoogleCidrs(raw), ['8.8.8.0/24', '104.154.0.0/15']);
  });

  test('bundled youtube-google.cidr asset parses non-empty IPv4 CIDRs', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cidrs = await loadYoutubeGoogleCidrs();
    expect(cidrs, isNotEmpty);
    expect(cidrs.every((c) => RegExp(r'^\d').hasMatch(c)), isTrue);
    expect(cidrs.every((c) => c.contains('/')), isTrue);
  });
}
