import 'dart:convert';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:crypto/crypto.dart';

import 'dart:math';

import 'oauth.dart' as oauth;

Future<QrImageView?> generateBasicQrCode() async {
  String? deviceId = await oauth.storage.read(key: "device_id");
  String? cardNumber = await oauth.storage.read(key: "card_number");

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

  return QrImageView(
    data: qrData,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
  );
}

String Guid() {
  const chars = '0123456789';

  Random rand = Random.secure();
  return String.fromCharCodes(
    Iterable.generate(3, (_) => chars.codeUnitAt(rand.nextInt(chars.length))),
  );
}
