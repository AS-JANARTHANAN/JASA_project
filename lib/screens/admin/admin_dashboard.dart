// lib/screens/admin/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:jasa_new/screens/add_product_screen.dart'; // ✅ Import Add Product Page

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final features = [
      {"title": "Add Product", "icon": Icons.add_box}, // ✅ Renamed for clarity
      {"title": "Manage Users", "icon": Icons.people},
      {"title": "Reports", "icon": Icons.bar_chart},
      {"title": "Settings", "icon": Icons.settings},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Admin Dashboard")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          itemCount: features.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (context, index) {
            final feature = features[index];
            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  if (feature["title"] == "Add Product") {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddProductScreen(),
                      ),
                    );
                  } else {
                    // 🚧 Later: Navigate to respective screen
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("${feature["title"]} coming soon!"),
                      ),
                    );
                  }
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      feature["icon"] as IconData,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      feature["title"] as String,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
