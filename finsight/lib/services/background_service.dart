import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sms_service.dart';
import 'api_service.dart';

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
        initialNotificationContent: 'Monitoring SMS in background',
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
    // We need to initialize services/bindings if not already
    // But ApiService and SmsService are static, so should be fine.

    // Note: Permission check might fail in background if not already granted.
    // We assume permissions are granted before service start.

    final lastSync = await SmsService.getLastSyncTimestamp();
    final newSms = await SmsService.fetchNewSms(lastSync);

    if (newSms.isNotEmpty) {
      final success = await ApiService.postSmsData(newSms);
      if (success) {
        await SmsService.saveLastSyncTimestamp();

        // Update notification via service if supported, or local notification
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: "FinSight Active",
            content: "Synced ${newSms.length} new SMS",
          );
        }

        // Also show local notification purely for visibility if service notification isn't enough
        // _updateNotification('Synced ${newSms.length} new SMS');
        // (Moved logic inside onStart context if needed, but setForegroundNotificationInfo is better)
      }
    }
  } catch (e) {
    print("[BackgroundService] Sync error: $e");
  }
}
