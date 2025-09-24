import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDarkMode = false; // Example setting

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Appearance Settings
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Appearance',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Enable or disable dark theme'),
                  secondary: const Icon(Icons.dark_mode_outlined),
                  value: _isDarkMode,
                  onChanged: (value) {
                    setState(() {
                      _isDarkMode = value;
                      // TODO: Implement actual theme change logic
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Theme change not implemented yet.')),
                      );
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // About Section
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'General',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About App'),
                  subtitle: const Text('View application details'),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'Jasa App',
                      applicationVersion: '1.0.0',
                      applicationLegalese: '© 2024 Jasa',
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 16.0),
                          child: Text('An app for managing sales and inventory.'),
                        )
                      ],
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Logout'),
                  subtitle: const Text('Sign out from your account'),
                  onTap: () {
                    // TODO: Implement logout functionality
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logout functionality not implemented yet.')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
