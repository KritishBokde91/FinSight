import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';

class SmsService {
  static const platform = MethodChannel('com.genzloop.finsight/sms');
  static const String _keyLastSync = 'last_sync_timestamp';
  static const String _keyIsFirstRun = 'is_first_run';
  static const String _keyPendingSms = 'pending_native_sms';

  /// Get all SMS messages from the device.
  static Future<List<Map<String, dynamic>>> fetchAllSms() async {
    try {
      final List<dynamic> result = await platform.invokeMethod('getAllSms');
      return result.cast<Map<Object?, Object?>>().map((e) {
        return e.map((key, value) => MapEntry(key.toString(), value));
      }).toList();
    } on PlatformException catch (e) {
      print("[SmsService] Failed to get all SMS: '${e.message}'.");
      return [];
    }
  }

  /// Get SMS messages received after [timestamp].
  static Future<List<Map<String, dynamic>>> fetchNewSms(int timestamp) async {
    try {
      final List<dynamic> result = await platform.invokeMethod('getSmsSince', {
        "timestamp": timestamp,
      });
      return result.cast<Map<Object?, Object?>>().map((e) {
        return e.map((key, value) => MapEntry(key.toString(), value));
      }).toList();
    } on PlatformException catch (e) {
      print("[SmsService] Failed to get new SMS: '${e.message}'.");
      return [];
    }
  }

  // ─── Sync Status ───────────────────────────────────────────────────

  static Future<bool> isFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsFirstRun) ?? true;
  }

  static Future<void> markFirstRunDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsFirstRun, false);
  }

  static Future<int> getLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLastSync) ?? 0;
  }

  static Future<void> saveLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_keyLastSync, now);
  }

  // ─── Pending Native SMS (from BroadcastReceiver) ───────────────────
  // Messages received when app was killed are stored by native receiver.
  // We need to fetch and process them.

  static Future<List<Map<String, dynamic>>> getPendingNativeSms() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_keyPendingSms);
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      print("[SmsService] Error parsing pending SMS: $e");
      return [];
    }
  }

  static Future<void> clearPendingNativeSms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPendingSms);
  }
}
