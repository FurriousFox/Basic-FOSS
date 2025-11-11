import 'package:url_launcher/url_launcher.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';

// String redirectUri = 'com.basicfit.trainingapp:/oauthredirect';
// String clientId = 'hMN33iw3DpHNg5VQaeNKoRUQKmIIvQV5vxOKba8AnrM';

// use iOS values on android, to prevent clashing redirect with both apps installed
String redirectUri = 'com.basicfit.bfa:/oauthredirect';
String clientId = 'q6KqjlQINmjOC86rqt9JdU_i41nhD_Z4DwygpBxGiIs';

final storage = FlutterSecureStorage();

String generateCodeVerifier([int length = 128]) {
  const charset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final rand = Random.secure();
  return List.generate(
    length,
    (_) => charset[rand.nextInt(charset.length)],
  ).join();
}

String generateCodeChallenge(String codeVerifier) {
  return base64UrlEncode(
    sha256.convert(utf8.encode(codeVerifier)).bytes,
  ).replaceAll('=', '');
}

Future<void> login() async {
  String codeVerifier = generateCodeVerifier();
  String codeChallenge = generateCodeChallenge(codeVerifier);

  if (!await launchUrl(
    Uri.parse(
      'https://login.basic-fit.com/?redirect_uri=${Uri.encodeComponent(redirectUri)}&client_id=${Uri.encodeComponent(clientId)}&response_type=code&app=true&code_challenge=${Uri.encodeComponent(codeChallenge)}&code_challenge_method=S256',
    ),
    mode: LaunchMode.inAppBrowserView,
  )) {
    throw Exception('Could not open browser.');
  } else {
    await storage.write(key: "code_verifier", value: codeVerifier);
  }
}

Future<void> code(Uri uri) async {
  String? code = uri.queryParameters['code'];
  if (code == null) {
    return;
  }

  String? codeVerifier = await storage.read(key: "code_verifier");
  if (codeVerifier == null) {
    return;
  } else {
    await storage.delete(key: "code_verifier");
  }

  HttpClient httpClient = HttpClient();
  HttpClientRequest tokenExchange = await httpClient.postUrl(
    Uri.parse('https://auth.basic-fit.com/token'),
  );
  tokenExchange.headers.set(
    "Content-Type",
    'application/x-www-form-urlencoded',
  );

  tokenExchange.write(
    'redirect_uri=${Uri.encodeComponent(redirectUri)}&client_id=${Uri.encodeComponent(clientId)}&grant_type=authorization_code&code=${Uri.encodeComponent(code)}&code_verifier=${Uri.encodeComponent(codeVerifier)}',
  );
  HttpClientResponse response = await tokenExchange.close();
  String responseBody = await response.transform(utf8.decoder).join();

  if (response.statusCode == 200) {
    Map<String, dynamic> jsonResponse = jsonDecode(responseBody);
    String accessToken = jsonResponse['access_token'];
    String refreshToken = jsonResponse['refresh_token'];

    await storage.write(key: "access_token", value: accessToken);
    await storage.write(key: "refresh_token", value: refreshToken);

    print('Access Token: $accessToken');
    print('Refresh Token: $refreshToken');

    var memberInfoRequest = await httpClient.getUrl(
      Uri.parse('https://bfa.basic-fit.com/api/member/info'),
    );
    memberInfoRequest.headers.set('Authorization', 'Bearer $accessToken');
    memberInfoRequest.headers.set('Bfa-Version', '1.79.5.2738');
    memberInfoRequest.headers.set(
      'User-Agent',
      'Basic Fit App/1.79.5.2738 (Android)',
    );
    memberInfoRequest.headers.set('Client-Id', clientId);
    memberInfoRequest.headers.set('Redirect-Uri', redirectUri);
    var memberInfoResponse = await memberInfoRequest.close();
    String memberInfoResponseBody = await memberInfoResponse
        .transform(utf8.decoder)
        .join();
    if (memberInfoResponse.statusCode == 200) {
      // check if response.member.deviceId isn't null
      Map<String, dynamic> memberInfoJson = jsonDecode(memberInfoResponseBody);

      if (memberInfoJson['member']?['deviceId'] != null &&
          memberInfoJson['member']?['cardnumber'] != null) {
        print('Device ID: ${memberInfoJson['member']['deviceId']}');
        await storage.write(
          key: "device_id",
          value: memberInfoJson['member']['deviceId'],
        );

        print('Card Number: ${memberInfoJson['member']['cardnumber']}');
        await storage.write(
          key: "card_number",
          value: memberInfoJson['member']['cardnumber'],
        );
      }
    }

    httpClient.close();
  } else {
    // TODO: visually indicate error

    throw Exception('Failed to get tokens: $responseBody');
  }
}

Future<bool> isLoggedIn() async {
  String? accessToken = await storage.read(key: "access_token");
  String? refreshToken = await storage.read(key: "refresh_token");
  String? deviceId = await storage.read(key: "device_id");
  String? cardNumber = await storage.read(key: "card_number");
  return accessToken != null &&
      refreshToken != null &&
      deviceId != null &&
      cardNumber != null;
}
