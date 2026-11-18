import 'package:flutter/services.dart';

class WearBridge {
  static const _channel = MethodChannel('nl.argv.basic_foss/wear');

  static Future<bool> get isWearDevice async {
    try {
      return await _channel.invokeMethod<bool>('isWearDevice') ?? false;
    } on PlatformException catch (error) {
      print('Wear: unable to identify device: $error');
      return false;
    }
  }

  static Future<Map<String, String>?> getStoredAuthData() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getStoredAuthData',
      );
      if (result == null) return null;
      return Map.fromEntries(
        result.entries
            .where((entry) => entry.value != null)
            .map(
              (entry) => MapEntry(
                entry.key.toString(),
                entry.value.toString(),
              ),
            ),
      );
    } on PlatformException catch (error) {
      print('Wear: unable to read stored phone data: $error');
      return null;
    }
  }

  static Future<void> requestAuthState() async {
    try {
      await _channel.invokeMethod<void>('requestAuthState');
    } on PlatformException catch (error) {
      print('Wear: unable to request phone data: $error');
    }
  }

  static Future<void> publishAuthState({
    required bool loggedIn,
    String? deviceId,
    String? secureDeviceId,
    String? cardNumber,
    bool qrAccessValid = true,
  }) async {
    try {
      await _channel.invokeMethod<void>('publishAuthState', {
        'loggedIn': loggedIn,
        'deviceId': deviceId,
        'secureDeviceId': secureDeviceId,
        'cardNumber': cardNumber,
        'qrAccessValid': qrAccessValid,
      });
    } on PlatformException catch (error) {
      print('Wear: unable to publish phone data: $error');
    }
  }

  static Future<void> setMaxBrightness() async {
    try {
      await _channel.invokeMethod<void>('setMaxBrightness');
    } on PlatformException catch (error) {
      print('Wear: unable to maximize screen brightness: $error');
    }
  }

  static Future<void> restoreBrightness() async {
    try {
      await _channel.invokeMethod<void>('restoreBrightness');
    } on PlatformException catch (error) {
      print('Wear: unable to restore screen brightness: $error');
    }
  }
}
