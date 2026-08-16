import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/config.dart';
import 'package:teremok_connect/core/support_contact.dart';

void main() {
  group('SupportContact.clipForChat', () {
    test('keeps short text intact', () {
      expect(SupportContact.clipForChat('hello'), 'hello');
    });

    test('keeps the tail under the share cap', () {
      final report = 'H' * 80 + 'T' * SupportContact.telegramShareMaxChars;
      final clipped = SupportContact.clipForChat(report);
      expect(clipped.length, SupportContact.telegramShareMaxChars);
      expect(clipped, contains('обрезано'));
      expect(clipped.endsWith('T' * 10), isTrue);
      expect(clipped.contains('H'), isFalse);
    });
  });

  group('SupportContact.composeChatUri', () {
    test('opens support username with prefilled text', () {
      final uri = SupportContact.composeChatUri('diag line');
      expect(uri.host, 't.me');
      expect(uri.path, '/${AppConfig.supportTelegramUsername}');
      expect(uri.queryParameters['text'], 'diag line');
    });
  });

  group('SupportContact.composeBotUri', () {
    test('opens the product bot without a text query', () {
      final uri = SupportContact.composeBotUri();
      expect(uri.host, 't.me');
      expect(uri.path, '/${AppConfig.telegramBotUsername}');
      expect(uri.queryParameters.containsKey('text'), isFalse);
    });
  });
}
