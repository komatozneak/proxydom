import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/utils/country_flags.dart';

void main() {
  group('countryTagFrom', () {
    test('takes an uppercase ISO code off the front', () {
      final tag = countryTagFrom('DE CompanyNet | Hysteria');
      expect(tag?.code, 'de');
      expect(tag?.title, 'CompanyNet | Hysteria');
      expect(tag?.flagEmoji, '🇩🇪');
    });

    test('takes a lowercase code too', () {
      final tag = countryTagFrom('de CompanyNet | Hysteria | Медиа');
      expect(tag?.code, 'de');
      expect(tag?.title, 'CompanyNet | Hysteria | Медиа');
    });

    test('a protocol in the middle is not a country', () {
      final tag = countryTagFrom('DE CompanyNet | WS | Резерв');
      expect(tag?.code, 'de');
      expect(tag?.title, 'CompanyNet | WS | Резерв');
      expect(countryTagFrom('CompanyNet | WS | Резерв'), isNull);
    });

    test('takes brackets and dashes as separators', () {
      expect(countryTagFrom('[DE] CompanyNet')?.title, 'CompanyNet');
      expect(countryTagFrom('(NL) CompanyNet')?.title, 'CompanyNet');
      expect(countryTagFrom('DE-CompanyNet')?.title, 'CompanyNet');
      expect(countryTagFrom('DE: CompanyNet')?.title, 'CompanyNet');
      expect(countryTagFrom('DE_CompanyNet')?.title, 'CompanyNet');
    });

    test('takes a flag emoji, alone or before a code', () {
      final emoji = countryTagFrom('🇩🇪 CompanyNet');
      expect(emoji?.code, 'de');
      expect(emoji?.title, 'CompanyNet');

      final both = countryTagFrom('🇩🇪 DE CompanyNet');
      expect(both?.code, 'de');
      expect(both?.title, 'CompanyNet');
    });

    test('keeps a name that only looks like a code', () {
      expect(countryTagFrom('DEDoVPN'), isNull);
      expect(countryTagFrom('Test Server'), isNull);
      expect(countryTagFrom('XX CompanyNet'), isNull);
      expect(countryTagFrom('CompanyNet | Hysteria'), isNull);
      expect(countryTagFrom('No lag server'), isNull);
      expect(countryTagFrom('In stock'), isNull);
      expect(countryTagFrom('It works'), isNull);
      expect(countryTagFrom('De CompanyNet'), isNull);
      expect(countryTagFrom('de companyNet'), isNull);
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
      expect(countryCodeForFlagValue('media'), isNull);
      expect(countryCodeForFlagValue('gaming'), isNull);
      expect(countryCodeForFlagValue('xx'), isNull);
    });
  });
}
