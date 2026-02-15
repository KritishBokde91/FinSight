import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sms_plugin_platform_interface.dart';

/// An implementation of [SmsPluginPlatform] that uses method channels.
class MethodChannelSmsPlugin extends SmsPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('sms_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
