// lib/services/auth_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Register a new user and create a profile row.
  /// Throws an Exception on failure with a helpful message.
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String role, // 'admin' or 'user'
  }) async {
    try {
      // 1) Sign up (this returns AuthResponse with .user and .session)
      final res = await _supabase.auth.signUp(email: email, password: password);

      // get the user (some setups may return session=null but user present)
      final user = res.user ?? res.session?.user;
      if (user == null) {
        // This could happen if signup didn't produce a user (rare) or there are email-confirmation flows.
        throw Exception(
          'Registration failed: no user object returned. '
          'If your project requires email confirmation, check your email to confirm the account.',
        );
      }

      // 2) Insert profile row into "profiles" table
      // NOTE: If Row Level Security (RLS) policies block inserts, this will throw.
      await _supabase.from('profiles').insert({
        'id': user.id,
        'full_name': name,
        'role': role,
      });

      // Success -> nothing to return
    } on AuthException catch (e) {
      // Auth-specific exception (if thrown by SDK)
      throw Exception('Auth error: ${e.message}');
    } catch (e) {
      // Generic catch - includes HTTP / Postgrest errors
      throw Exception('Registration failed: ${e.toString()}');
    }
  }
}
