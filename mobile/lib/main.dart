import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config.dart';

void main() {
  // Проверочный print — в логах flutter run должно быть:
  //   [Teremok Connect] baseUrl=http://10.0.2.2:8000/api/v1
  // Если для физического Android — adb reverse tcp:8000 tcp:8000 + поменяй baseUrl
  // ignore: avoid_print
  print('[Teremok Connect] baseUrl=${AppConfig.baseUrl}');

  runApp(const TeremokApp());
}
