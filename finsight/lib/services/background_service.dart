import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'sms_service.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'auth_service.dart';

class BackgroundService {
  static const String notificationChannelId = 'finsight_service_channel';
  static const int notificationId = 888;

  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'FinSight Background Service',
      description: 'Running in background to sync SMS',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // We start manually after permissions
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'FinSight Active',
        initialNotificationContent: 'Monitoring SMS & UPI in background',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  static Future<void> start() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
  }
}

// Top-level functions for background execution
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Periodic sync
  Timer.periodic(const Duration(minutes: 15), (timer) async {
    await _performBackgroundSync(service);
  });

  // Also sync immediately on start
  await _performBackgroundSync(service);
}

Future<void> _performBackgroundSync(ServiceInstance service) async {
  try {
    final userId = await AuthService.getUserId();

    // 1. Sync SMS
    final lastSync = await SmsService.getLastSyncTimestamp();
    final newSms = await SmsService.fetchNewSms(lastSync);

    int syncedCount = 0;
    if (newSms.isNotEmpty) {
      final success = await ApiService.postSmsData(newSms);
      if (success) {
        await SmsService.saveLastSyncTimestamp();
        syncedCount += newSms.length;
      }
    }

    // 2. Sync UPI notifications
    final notifTxns = await NotificationService.syncNotifications(
      userId: userId,
    );

    // Update notification
    final total = syncedCount + notifTxns;
    if (total > 0 && service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "FinSight Active",
        content: "Synced $syncedCount SMS, $notifTxns UPI transactions",
      );
    }
  } catch (e) {
    debugPrint("[BackgroundService] Sync error: $e");
  }
}
