import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
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

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  // Top-level function for background execution
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    // Only available for flutter_background_service > 4.0.0
    // service.on('stopService').listen((event) {
    //   service.stopSelf();
    // });

    // Periodic sync
    Timer.periodic(const Duration(minutes: 15), (timer) async {
      await _performBackgroundSync();
    });

    // Also sync immediately on start
    await _performBackgroundSync();
  }

  static Future<void> _performBackgroundSync() async {
    try {
      if (await Permission.sms.status.isGranted) {
        final lastSync = await SmsService.getLastSyncTimestamp();
        final newSms = await SmsService.fetchNewSms(lastSync);

        if (newSms.isNotEmpty) {
          final success = await ApiService.postSmsData(newSms);
          if (success) {
            await SmsService.saveLastSyncTimestamp();
            _updateNotification('Synced ${newSms.length} new SMS');
          }
        }
      }
    } catch (e) {
      print("[BackgroundService] Sync error: $e");
    }
  }

  static Future<void> _updateNotification(String message) async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    flutterLocalNotificationsPlugin.show(
      notificationId,
      'FinSight Active',
      message,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          notificationChannelId,
          'FinSight Background Service',
          icon: 'ic_bg_service_small',
          ongoing: true,
        ),
      ),
    );
  }
}
