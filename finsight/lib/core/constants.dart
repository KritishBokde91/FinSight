/// Central configuration constants for the FinSight app.
class AppConstants {
  // ── Backend API ──────────────────────────────────────────────
  /// Your local backend running on the same machine.
  /// Use your computer's local IP so the phone can reach it.
  /// Find it with: ip addr | grep inet
  static const String apiBaseUrl = 'http://10.237.193.60:8080';
  static const String smsEndpoint = '$apiBaseUrl/api/sms';

  // ── SharedPreferences keys ───────────────────────────────────
  static const String lastSyncTimestampKey = 'last_sync_timestamp';
  static const String isFirstRunKey = 'is_first_run';
  static const String pendingSmsKey = 'pending_native_sms';

  // ── Background service ───────────────────────────────────────
  static const String notificationChannelId = 'finsight_bg_service';
  static const String notificationChannelName = 'FinSight SMS Sync';
  static const int notificationId = 888;

  // ── API config ───────────────────────────────────────────────
  static const int apiTimeoutSeconds = 30;
  static const int maxRetries = 3;
  static const int batchSize = 50; // SMS per API call
}
