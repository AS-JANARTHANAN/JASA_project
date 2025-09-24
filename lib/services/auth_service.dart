// lib/services/auth_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<String> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = res.user;
      if (user == null) {
        throw Exception('Login failed: no user object returned.');
      }

      // Fetch the user's role from the 'profiles' table
      final profileRes = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();

      return profileRes['role'] as String;
    } on AuthException catch (e) {
      throw Exception('Auth error: ${e.message}');
    } catch (e) {
      throw Exception('Login failed: ${e.toString()}');
    }
  }

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

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      throw Exception('Logout failed: ${e.toString()}');
    }
  }
}
