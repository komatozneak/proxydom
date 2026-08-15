import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pending `teremokconnect://join?code=` payload (ADR 011).
final seatJoinCodeProvider = StateProvider<String?>((ref) => null);
