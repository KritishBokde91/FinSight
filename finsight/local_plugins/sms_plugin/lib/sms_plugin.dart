
import 'sms_plugin_platform_interface.dart';

class SmsPlugin {
  Future<String?> getPlatformVersion() {
    return SmsPluginPlatform.instance.getPlatformVersion();
  }
}
