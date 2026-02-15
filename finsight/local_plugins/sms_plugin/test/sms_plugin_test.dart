import 'package:flutter_test/flutter_test.dart';
import 'package:sms_plugin/sms_plugin.dart';
import 'package:sms_plugin/sms_plugin_platform_interface.dart';
import 'package:sms_plugin/sms_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSmsPluginPlatform
    with MockPlatformInterfaceMixin
    implements SmsPluginPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final SmsPluginPlatform initialPlatform = SmsPluginPlatform.instance;

  test('$MethodChannelSmsPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSmsPlugin>());
  });

  test('getPlatformVersion', () async {
    SmsPlugin smsPlugin = SmsPlugin();
    MockSmsPluginPlatform fakePlatform = MockSmsPluginPlatform();
    SmsPluginPlatform.instance = fakePlatform;

    expect(await smsPlugin.getPlatformVersion(), '42');
  });
}
