import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              AppRouter.setAuthenticated(false);
              context.go('/login');
            },
            tooltip: 'Выйти',
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 96, color: Colors.teal),
            SizedBox(height: 24),
            Text(
              'Home Screen',
              style: TextStyle(fontSize: 28),
            ),
            SizedBox(height: 8),
            Text(
              '(VPN UI — в шагах 9+)',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
