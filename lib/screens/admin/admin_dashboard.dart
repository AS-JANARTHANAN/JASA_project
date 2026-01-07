// lib/screens/admin/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:JASA/services/auth_service.dart';
import 'package:JASA/screens/add_product_screen.dart';
import 'package:JASA/screens/admin/bill_history_screen.dart';
import 'package:JASA/screens/admin/gst_bill_screen.dart';
import 'package:JASA/screens/admin/manage_stocks_screen.dart';
import 'package:JASA/screens/admin/manage_users_screen.dart';
import 'package:JASA/screens/admin/pending_bills_screen.dart';
import 'package:JASA/screens/admin/reports_screen.dart';
import 'package:JASA/screens/admin/view_product_screen.dart';
import 'package:JASA/screens/billing_screen.dart';
import 'package:JASA/screens/admin/settings_screen.dart';
import 'package:JASA/widgets/sync_status_widget.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final features = [
      {"title": "Billing", "icon": Icons.receipt_long_outlined, "screen": const BillingScreen()},
      {"title": "Bill History", "icon": Icons.history_outlined, "screen": const BillHistoryScreen()},
      {"title": "GST Bill", "icon": Icons.account_balance_outlined, "screen": const GSTBillScreen()},
      {"title": "Pending Bills", "icon": Icons.cloud_sync_outlined, "screen": const PendingBillsScreen()},
      {"title": "Add Product", "icon": Icons.add_box_outlined, "screen": const AddProductScreen()},
      {"title": "View Products", "icon": Icons.view_list_outlined, "screen": const ViewProductScreen()},
      {"title": "Manage Stocks", "icon": Icons.inventory_2_outlined, "screen": const ManageStocksScreen()},
      {"title": "Manage Users", "icon": Icons.people_outline, "screen": const ManageUsersScreen()},
      {"title": "Reports", "icon": Icons.bar_chart_outlined, "screen": ReportsScreen()},
      {"title": "Settings", "icon": Icons.settings_outlined, "screen": const SettingsScreen()},
    ];

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        title: Text(
          "Admin Dashboard",
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: "Logout",
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome, Admin!",
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Here's an overview of your business.",
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Sync Status Banner (only shows if offline or pending)
          const SyncStatusBanner(),
          
          const SizedBox(height: 16),

          // Grid Menu
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: features.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
            ),
            itemBuilder: (context, index) {
              final feature = features[index];
              return InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  final screen = feature["screen"] as Widget?;
                  if (screen != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => screen),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("${feature["title"]} coming soon!"),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        feature["icon"] as IconData,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        feature["title"] as String,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}