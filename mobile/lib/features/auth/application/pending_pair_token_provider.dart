import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pending bot-first pair token from `teremokconnect://pair?token=`.
final pendingPairTokenProvider = StateProvider<String?>((ref) => null);
