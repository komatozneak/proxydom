import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/referral_api.dart';

final referralApiProvider = Provider<ReferralApi>((ref) => ReferralApi());

/// Pending `teremokconnect://ref?code=` (and landing clipboard later).
final pendingReferralCodeProvider = StateProvider<String?>((ref) => null);
