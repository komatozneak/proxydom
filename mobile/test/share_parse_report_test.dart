import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/share_link_parser.dart';

void main() {
  test('a hopping line is counted instead of disappearing', () {
    const body = '''
hysteria2://secret@45.88.12.111:443/?sni=crt.onecloudstream.com#de
hysteria2://secret@138.124.242.247:443,5000-6000/?sni=crt.onecloudstream.com#hop
''';
    final report = inspectShareSubscription(body);
    expect(report.links, hasLength(1));
    expect(report.skipped, hasLength(1));
    expect(report.skipped.single.reason, isNotEmpty);
    final note = formatUnsupportedImport(
      countLine:
          'read ${report.links.length}, unsupported ${report.skipped.length}',
      skipped: report.skipped,
    );
    expect(note, contains('unsupported 1'));
    expect(note, contains(report.skipped.single.reason));
    expect(note, isNot(contains('secret')));
  });
}
