/// Страны с Flash Call через Zvonok (RU, BY).
class PhoneCountry {
  const PhoneCountry({
    required this.isoCode,
    required this.flagEmoji,
    required this.dialCode,
    required this.nationalDigits,
  });

  final String isoCode;
  final String flagEmoji;
  final String dialCode;
  final int nationalDigits;

  String get displayPrefix => '$flagEmoji $dialCode';

  String toE164(String nationalDigits) => '$dialCode$nationalDigits';

  bool isValidNational(String digits) {
    if (digits.length != nationalDigits) return false;
    return RegExp(r'^\d+$').hasMatch(digits);
  }

  static const List<PhoneCountry> zvonokPool = [
    PhoneCountry(
      isoCode: 'RU',
      flagEmoji: '🇷🇺',
      dialCode: '+7',
      nationalDigits: 10,
    ),
    PhoneCountry(
      isoCode: 'BY',
      flagEmoji: '🇧🇾',
      dialCode: '+375',
      nationalDigits: 9,
    ),
  ];

  static PhoneCountry get defaultCountry => zvonokPool.first;

  static PhoneCountry? tryParseE164(String phone) {
    final normalized = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    // Longer dial codes first so +375 wins over a bare +7 prefix match.
    final ordered = [...zvonokPool]
      ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
    for (final country in ordered) {
      if (!normalized.startsWith(country.dialCode)) continue;
      final national = normalized.substring(country.dialCode.length);
      if (country.isValidNational(national)) return country;
    }
    return null;
  }
}
