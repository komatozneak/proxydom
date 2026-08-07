import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Legacy entry: routes to the Locations tab (bottom sheet removed).
Future<void> showRegionPicker(BuildContext context, WidgetRef ref) async {
  context.push('/locations');
}
