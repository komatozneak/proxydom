import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/utils/country_flags.dart';

void main() {
  group('countryTagFrom', () {
    test('takes an uppercase ISO code off the front', () {
      final tag = countryTagFrom('DE DoDoVPN | Hysteria');
      expect(tag?.code, 'de');
      expect(tag?.title, 'DoDoVPN | Hysteria');
      expect(tag?.flagEmoji, '🇩🇪');
    });

    test('takes a lowercase code too', () {
      final tag = countryTagFrom('de DoDoVPN | Hysteria | YouTube');
      expect(tag?.code, 'de');
      expect(tag?.title, 'DoDoVPN | Hysteria | YouTube');
    });

    test('a protocol in the middle is not a country', () {
      final tag = countryTagFrom('DE DoDoVPN | WS | Резерв');
      expect(tag?.code, 'de');
      expect(tag?.title, 'DoDoVPN | WS | Резерв');
      expect(countryTagFrom('DoDoVPN | WS | Резерв'), isNull);
    });

    test('takes brackets and dashes as separators', () {
      expect(countryTagFrom('[DE] DoDoVPN')?.title, 'DoDoVPN');
      expect(countryTagFrom('(NL) DoDoVPN')?.title, 'DoDoVPN');
      expect(countryTagFrom('DE-DoDoVPN')?.title, 'DoDoVPN');
      expect(countryTagFrom('DE: DoDoVPN')?.title, 'DoDoVPN');
      expect(countryTagFrom('DE_DoDoVPN')?.title, 'DoDoVPN');
    });

    test('takes a flag emoji, alone or before a code', () {
      final emoji = countryTagFrom('🇩🇪 DoDoVPN');
      expect(emoji?.code, 'de');
      expect(emoji?.title, 'DoDoVPN');

      final both = countryTagFrom('🇩🇪 DE DoDoVPN');
      expect(both?.code, 'de');
      expect(both?.title, 'DoDoVPN');
    });

    test('keeps a name that only looks like a code', () {
      expect(countryTagFrom('DEDoVPN'), isNull);
      expect(countryTagFrom('Test Server'), isNull);
      expect(countryTagFrom('XX DoDoVPN'), isNull);
      expect(countryTagFrom('DoDoVPN | Hysteria'), isNull);
      expect(countryTagFrom('No lag server'), isNull);
      expect(countryTagFrom('In stock'), isNull);
      expect(countryTagFrom('It works'), isNull);
      expect(countryTagFrom('De DoDoVPN'), isNull);
      expect(countryTagFrom('de doDoVPN'), isNull);
    });

    test('accepts the aliases providers use', () {
      expect(countryTagFrom('UK London')?.code, 'gb');
      expect(countryTagFrom('USA East')?.code, 'us');
      expect(countryTagFrom('UAE Dubai')?.code, 'ae');
      expect(countryTagFrom('EU West')?.code, 'eu');
    });

    test('a lone code keeps the text instead of blanking the row', () {
      final tag = countryTagFrom('DE');
      expect(tag?.code, 'de');
      expect(tag?.title, 'DE');
    });
  });

  group('flag values', () {
    test('code to emoji and back', () {
      expect(flagEmojiForCountryCode('de'), '🇩🇪');
      expect(flagEmojiForCountryCode('UK'), '🇬🇧');
      expect(countryCodeForFlagValue('🇷🇺'), 'ru');
      expect(countryCodeForFlagValue('ru'), 'ru');
      expect(countryCodeForFlagValue('🇺🇸'), 'us');
    });

    test('anything that is not a country is not a flag', () {
      expect(countryCodeForFlagValue('🌍'), isNull);
      expect(countryCodeForFlagValue('youtube'), isNull);
      expect(countryCodeForFlagValue('gaming'), isNull);
      expect(countryCodeForFlagValue('xx'), isNull);
    });
  });
}
