// lib/screens/register_screen.dart
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String? _role; // 'admin' or 'user'
  bool _loading = false;
  final _authService = AuthService();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a role')));
      return;
    }

    setState(() => _loading = true);

    try {
      await _authService.register(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        role: _role!,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registered successfully. Please login.')),
      );

      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background, // Consistent background
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16), // Reduced padding
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 400, // Reduced max width
              ), 
              padding: const EdgeInsets.all(24), // Reduced inner padding
              decoration: BoxDecoration(
                color: theme.colorScheme.surface, // Consistent surface color
                borderRadius: BorderRadius.circular(
                  24,
                ), // Consistent rounded corners
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withOpacity(
                      0.1,
                    ), // Consistent softer shadow
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App Logo/Title
                    Icon(
                      Icons.person_add_alt_1_outlined, // Icon for registration
                      size: 60, // Reduced icon size
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Create Account",
                      style: theme.textTheme.headlineSmall?.copyWith( // Reduced font size
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Register to get started",
                      style: theme.textTheme.bodyMedium?.copyWith( // Reduced font size
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24), // Reduced spacing
                    // Name
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Full name',
                        hintText: "Enter your full name",
                        prefixIcon: const Icon(Icons.person_outline),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceVariant.withOpacity(
                          0.3,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0), // Reduced padding
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Name is required'
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // Email
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        hintText: "Enter your email",
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceVariant.withOpacity(
                          0.3,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0), // Reduced padding
                      ),
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 12),

                    // Password
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: "Create a password",
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceVariant.withOpacity(
                          0.3,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0), // Reduced padding
                      ),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 12),

                    // Role
                    DropdownButtonFormField<String>(
                      value: _role, // Use value instead of initialValue
                      decoration: InputDecoration(
                        labelText: 'Role',
                        hintText: "Select your role",
                        prefixIcon: const Icon(Icons.assignment_ind_outlined),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceVariant.withOpacity(
                          0.3,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0), // Reduced padding
                      ),
                      items: const [
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                        DropdownMenuItem(value: 'user', child: Text('User')),
                      ],
                      onChanged: (v) => setState(() => _role = v),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Please choose a role'
                          : null,
                    ),
                    const SizedBox(height: 24), // Reduced spacing
                    // Register button
                    SizedBox(
                      width: double.infinity,
                      height: 48, // Reduced height
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 5,
                        ),
                        onPressed: _loading ? null : _register,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Register Now',
                                style: theme.textTheme.titleMedium?.copyWith( // Reduced font size
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16), // Reduced spacing
                    // Login link
                    Wrap( // Used Wrap for responsiveness
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          "Already have an account?",
                          style: theme.textTheme.bodyMedium, // Reduced font size
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacementNamed(context, '/login');
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            textStyle: theme.textTheme.bodyMedium?.copyWith( // Reduced font size
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: const Text("Login"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
