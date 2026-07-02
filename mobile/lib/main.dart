import 'package:flutter/material.dart';

void main() {
  runApp(const TeremokApp());
}

class TeremokApp extends StatelessWidget {
  const TeremokApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teremok Connect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const _HelloScreen(),
    );
  }
}

class _HelloScreen extends StatelessWidget {
  const _HelloScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teremok Connect')),
      body: const Center(
        child: Text(
          'Hello Teremok',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
        ),
      ),
    );
  }
}
