import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'sms_plugin_method_channel.dart';

abstract class SmsPluginPlatform extends PlatformInterface {
  /// Constructs a SmsPluginPlatform.
  SmsPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static SmsPluginPlatform _instance = MethodChannelSmsPlugin();

  /// The default instance of [SmsPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelSmsPlugin].
  static SmsPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SmsPluginPlatform] when
  /// they register themselves.
  static set instance(SmsPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
