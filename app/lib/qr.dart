import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'dart:math';

import 'oauth.dart' as oauth;

Future<String?> generateBasicQrData({
  String? deviceId,
  String? cardNumber,
}) async {
  if (deviceId == null) {
    deviceId = (await oauth.ensureDeviceIds())['deviceId'];
  }
  cardNumber ??= await oauth.storage.read(key: "card_number");

  if (deviceId == null || cardNumber == null) {
    return null;
  }

  int unixTimestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000)
      .floor();
  unixTimestamp += -3;
  String guid = Guid();
  String hashInput = '$cardNumber$guid$unixTimestamp$deviceId';
  String hash = sha256
      .convert(utf8.encode(hashInput))
      .toString()
      .toUpperCase()
      .substring(56);
  String qrData = 'GM2:$cardNumber:$guid:$unixTimestamp:$hash';

  return qrData;
}

String Guid() {
  const chars = '0123456789';

  Random rand = Random.secure();
  return String.fromCharCodes(
    Iterable.generate(3, (_) => chars.codeUnitAt(rand.nextInt(chars.length))),
  );
}
