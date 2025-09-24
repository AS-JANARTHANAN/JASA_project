// lib/screens/user/user_dashboard.dart
import 'package:flutter/material.dart';
import 'package:JASA/services/auth_service.dart';
import 'package:JASA/screens/billing_screen.dart';

class UserDashboard extends StatelessWidget {
  const UserDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Billing System"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await AuthService().signOut();
                Navigator.of(context).pushReplacementNamed('/splash');
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Logout failed: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.receipt_long),
          label: const Text('Create New Bill'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
            textStyle: Theme.of(context).textTheme.headlineSmall,
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BillingScreen()),
            );
          },
        ),
      ),
    );
  }
}