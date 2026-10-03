import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/config.dart';
import 'package:proxydom/core/support_contact.dart';

void main() {
  test('support page is the public contact URL', () {
    expect(SupportContact.supportPageUri(), Uri.parse(AppConfig.supportPageUrl));
    expect(SupportContact.supportPageUri().host, 'proxydom.su');
    expect(SupportContact.supportPageUri().path, '/support.html');
  });
}
