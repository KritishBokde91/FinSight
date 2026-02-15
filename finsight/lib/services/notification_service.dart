import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

/// Service that reads captured UPI notifications from SharedPreferences
/// (written by Android NotificationListenerService) and forwards them
/// to the backend API.
class NotificationService {
  static const _pendingKey = 'pending_notifications';

  /// Read and clear pending UPI notifications, then post to backend.
  /// Returns the number of new transactions created.
  static Future<int> syncNotifications({String? userId}) async {
    try {
      // Read from native SharedPreferences (not Flutter's)
      // The Android service writes to its own prefs file
      final prefs = await SharedPreferences.getInstance();
      // We use the Flutter prefs to bridge — the Android side stores in
      // a separate prefs file. We read it via platform channel.
      // For now, use a simpler approach: read from the native prefs
      // directly through the same SharedPreferences instance.

      final pendingJson = prefs.getString(_pendingKey);
      if (pendingJson == null || pendingJson == '[]') {
        debugPrint('[NotificationService] No pending notifications');
        return 0;
      }

      final List<dynamic> notifications = jsonDecode(pendingJson);
      if (notifications.isEmpty) return 0;

      debugPrint(
        '[NotificationService] Found ${notifications.length} pending UPI notifications',
      );

      // Post to backend
      final response = await http
          .post(
            Uri.parse('${AppConstants.apiBaseUrl}/api/notifications'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'data': notifications, 'user_id': userId}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final newTxns = body['new_transactions'] ?? 0;

        // Clear pending notifications
        await prefs.remove(_pendingKey);

        debugPrint(
          '[NotificationService] Synced: $newTxns new transactions from notifications',
        );
        return newTxns;
      } else {
        debugPrint(
          '[NotificationService] Backend error: ${response.statusCode}',
        );
        return 0;
      }
    } catch (e) {
      debugPrint('[NotificationService] Sync error: $e');
      return 0;
    }
  }

  /// Check if notification listener permission is granted.
  /// Users must manually enable it in Settings → Notification access.
  static Future<bool> isNotificationAccessGranted() async {
    // This would need a platform channel to check
    // NotificationManagerCompat.getEnabledListenerPackages()
    // For now, we'll rely on the user enabling it manually
    return true; // placeholder
  }
}
