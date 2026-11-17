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
      return result.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
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
    String? cardNumber,
  }) async {
    try {
      await _channel.invokeMethod<void>('publishAuthState', {
        'loggedIn': loggedIn,
        'deviceId': deviceId,
        'cardNumber': cardNumber,
      });
    } on PlatformException catch (error) {
      print('Wear: unable to publish phone data: $error');
    }
  }
}
