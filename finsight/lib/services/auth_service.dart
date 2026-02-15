import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

/// Manages user authentication state and API calls (email-based).
class AuthService {
  static const _keyUserId = 'finsight_user_id';
  static const _keyEmail = 'finsight_user_email';
  static const _keyName = 'finsight_user_name';

  /// Check if user is logged in.
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId) != null;
  }

  /// Get stored user ID.
  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId);
  }

  /// Get stored display name.
  static Future<String?> getDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyName);
  }

  /// Get stored email.
  static Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmail);
  }

  /// Sign up a new user with email.
  static Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/api/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'display_name': displayName,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final user = data['user'];
      await _saveUser(user);
      return user;
    } else if (response.statusCode == 409) {
      throw Exception('Email already registered');
    } else {
      final body = jsonDecode(response.body);
      throw Exception(body['detail'] ?? 'Signup failed');
    }
  }

  /// Log in with email and password.
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final user = data['user'];
      await _saveUser(user);
      return user;
    } else if (response.statusCode == 401) {
      throw Exception('Invalid password');
    } else if (response.statusCode == 404) {
      throw Exception('User not found');
    } else {
      final body = jsonDecode(response.body);
      throw Exception(body['detail'] ?? 'Login failed');
    }
  }

  /// Log out.
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyName);
  }

  /// Fetch user profile from API.
  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('${AppConstants.apiBaseUrl}/api/auth/user/$userId'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['user'] as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  /// Save user data locally.
  static Future<void> _saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, user['id'] ?? '');
    await prefs.setString(_keyEmail, user['email'] ?? '');
    await prefs.setString(
      _keyName,
      user['display_name'] ?? user['email']?.split('@')[0] ?? '',
    );
  }
}
