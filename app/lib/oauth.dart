import 'package:url_launcher/url_launcher.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';
import 'main.dart' show globalAppState, LoginStatus;

String redirectUri = 'com.basicfit.bfa:/oauthredirect';
String clientId = 'q6KqjlQINmjOC86rqt9JdU_i41nhD_Z4DwygpBxGiIs';
const basicFitUserAgent = 'Basic Fit App/1.79.5.2738 (Android)';

final storage = FlutterSecureStorage();

String? _lastProcessedCode;
String? _activeCodeVerifier;
Completer<bool>? _refreshCompleter;

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
  if (globalAppState?.loginStatus == LoginStatus.loggingIn) return;
  globalAppState?.setLoginStatus(LoginStatus.loggingIn);

  String codeVerifier = generateCodeVerifier();
  String codeChallenge = generateCodeChallenge(codeVerifier);
  _activeCodeVerifier = codeVerifier;

  // Persist the verifier before opening the browser. The callback can arrive
  // immediately when an existing browser session is already authenticated.
  try {
    await storage.write(key: "code_verifier", value: codeVerifier);
    if (!await launchUrl(
      Uri.parse(
        'https://login.basic-fit.com/?redirect_uri=${Uri.encodeComponent(redirectUri)}&client_id=${Uri.encodeComponent(clientId)}&response_type=code&app=true&code_challenge=${Uri.encodeComponent(codeChallenge)}&code_challenge_method=S256',
      ),
      mode: LaunchMode.inAppBrowserView,
    )) {
      throw Exception('Could not open browser.');
    }
  } catch (error) {
    _activeCodeVerifier = null;
    await storage.delete(key: "code_verifier");
    globalAppState?.setLoginStatus(LoginStatus.failed);
    rethrow;
  }
}

Future<void> code(Uri uri) async {
  try {
    // Close the in-app browser first to free up the UI
    closeInAppWebView();

    // Small delay to let the browser close
    await Future.delayed(const Duration(milliseconds: 100));

    globalAppState?.setLoginStatus(LoginStatus.loggingIn);

    String? code = uri.queryParameters['code'];
    if (code == null) {
      if (uri.queryParameters['error'] != null) {
        print(
          'Login was rejected: ${uri.queryParameters['error_description'] ?? uri.queryParameters['error']}',
        );
        globalAppState?.setLoginStatus(LoginStatus.failed);
      }
      return;
    }

    // Prevent processing the same code twice
    if (code == _lastProcessedCode) {
      return;
    }
    _lastProcessedCode = code;

    String? codeVerifier =
        _activeCodeVerifier ?? await storage.read(key: "code_verifier");
    if (codeVerifier == null) {
      print('No code verifier found');
      globalAppState?.setLoginStatus(LoginStatus.failed);
      return;
    }

    // Perform token exchange in a microtask to avoid blocking
    try {
      await _performTokenExchange(code, codeVerifier);
    } finally {
      _activeCodeVerifier = null;
      await storage.delete(key: "code_verifier");
    }
  } catch (e) {
    print('Error in code(): $e');
    globalAppState?.setLoginStatus(LoginStatus.failed);
  }
}

Future<void> _performTokenExchange(String code, String codeVerifier) async {
  HttpClient httpClient = HttpClient();
  httpClient.userAgent = basicFitUserAgent;
  try {
    HttpClientRequest tokenExchange = await httpClient.postUrl(
      Uri.parse('https://auth.basic-fit.com/token'),
    );
    tokenExchange.headers.set(
      "Content-Type",
      'application/x-www-form-urlencoded',
    );
    tokenExchange.headers.set(
      HttpHeaders.userAgentHeader,
      basicFitUserAgent,
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

      // print('Access Token: $accessToken');
      // print('Refresh Token: $refreshToken');

      if (!await isLoggedIn()) await _fetchMemberInfo(httpClient, accessToken);
    } else {
      globalAppState?.setLoginStatus(LoginStatus.failed);
      throw Exception('Failed to get tokens: $responseBody');
    }
  } finally {
    httpClient.close();
  }
}

Future<void> _fetchMemberInfo(HttpClient httpClient, String accessToken) async {
  var memberInfoRequest = await httpClient.getUrl(
    Uri.parse('https://bfa.basic-fit.com/api/member/info'),
  );
  memberInfoRequest.headers.set('Authorization', 'Bearer $accessToken');
  memberInfoRequest.headers.set('Bfa-Version', '1.79.5.2738');
  memberInfoRequest.headers.set(
    'User-Agent',
    basicFitUserAgent,
  );
  memberInfoRequest.headers.set('Client-Id', clientId);
  memberInfoRequest.headers.set('Redirect-Uri', redirectUri);
  var memberInfoResponse = await memberInfoRequest.close();
  String memberInfoResponseBody = await memberInfoResponse
      .transform(utf8.decoder)
      .join();
  if (memberInfoResponse.statusCode == 200) {
    Map<String, dynamic> memberInfoJson = jsonDecode(memberInfoResponseBody);

    if (memberInfoJson['member']?['deviceId'] != null &&
        memberInfoJson['member']?['cardnumber'] != null) {
      // print('Device ID: ${memberInfoJson['member']['deviceId']}');
      await storage.write(
        key: "device_id",
        value: memberInfoJson['member']['deviceId'],
      );

      // print('Card Number: ${memberInfoJson['member']['cardnumber']}');
      await storage.write(
        key: "card_number",
        value: memberInfoJson['member']['cardnumber'],
      );

      // Immediately refresh the QR code after successful login
      await globalAppState?.refreshQrCode();
    } else {
      globalAppState?.setLoginStatus(LoginStatus.failed);
    }
  } else {
    globalAppState?.setLoginStatus(LoginStatus.failed);
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

Future<bool> hasAuthenticatedSession() async {
  return await storage.read(key: "access_token") != null;
}

Future<bool> setDeviceId(
  String deviceId, {
  String deviceDescription = 'Basic-FOSS',
}) async {
  final normalizedDeviceId = deviceId.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{36}$').hasMatch(normalizedDeviceId)) {
    throw const FormatException(
      'Device ID must contain 36 hexadecimal characters.',
    );
  }

  final accessToken = await storage.read(key: 'access_token');
  if (accessToken == null) {
    throw Exception('No access token available.');
  }

  final httpClient = HttpClient()..userAgent = basicFitUserAgent;
  try {
    final request = await httpClient.postUrl(
      Uri.parse('https://bfa.basic-fit.com/api/member/deviceInfo'),
    );
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $accessToken',
    );
    request.headers.set('Bfa-Version', '1.79.5.2738');
    request.headers.set(HttpHeaders.userAgentHeader, basicFitUserAgent);
    request.headers.set('Client-Id', clientId);
    request.headers.set('Redirect-Uri', redirectUri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'deviceId': normalizedDeviceId,
      'deviceDescription': deviceDescription,
    }));

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 204 && response.statusCode != 424) {
      throw Exception(
        'Failed to set device ID (HTTP ${response.statusCode}): $responseBody',
      );
    }

    // The API documents that a 424 can still mean a non-empty ID was applied.
    await _fetchMemberInfo(httpClient, accessToken);
    if (await storage.read(key: 'device_id') != normalizedDeviceId ||
        !await isLoggedIn()) {
      throw Exception('Member info did not contain complete QR credentials.');
    }
    return true;
  } finally {
    httpClient.close();
  }
}

/// Decodes the payload of a JWT token without verification
Map<String, dynamic>? decodeJwtPayload(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;

    final payload = parts[1];
    // Add padding if needed
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(decoded);
  } catch (e) {
    return null;
  }
}

/// Checks if the access token is expired or will expire within [bufferSeconds]
Future<bool> isTokenExpired({int bufferSeconds = 60}) async {
  String? accessToken = await storage.read(key: "access_token");
  if (accessToken == null) return true;

  final payload = decodeJwtPayload(accessToken);
  if (payload == null || payload['exp'] == null) return true;
  final expValue = payload['exp'];
  int exp;
  if (expValue is int) {
    exp = expValue;
  } else if (expValue is double) {
    exp = expValue.toInt();
  } else if (expValue is String) {
    exp = int.tryParse(expValue) ?? 0;
  } else {
    return true;
  }

  final expiryTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
  final now = DateTime.now().add(Duration(seconds: bufferSeconds));

  return now.isAfter(expiryTime);
}

/// Refreshes the access token using the stored refresh token
Future<bool> refreshAccessToken({bool openFriendsOnFailure = false}) async {
  if (_refreshCompleter != null) {
    return _refreshCompleter!.future;
  }

  _refreshCompleter = Completer<bool>();
  bool result = false;

  String? refreshToken = await storage.read(key: "refresh_token");
  if (refreshToken == null) {
    _refreshCompleter!.complete(false);
    _refreshCompleter = null;
    return false;
  }

  HttpClient httpClient = HttpClient();
  httpClient.userAgent = basicFitUserAgent;
  try {
    HttpClientRequest request = await httpClient.postUrl(
      Uri.parse('https://auth.basic-fit.com/token'),
    );
    request.headers.set("Content-Type", 'application/x-www-form-urlencoded');
    request.headers.set("Accept", 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, basicFitUserAgent);

    request.write(
      'refresh_token=${Uri.encodeComponent(refreshToken)}&grant_type=refresh_token&redirect_uri=${Uri.encodeComponent(redirectUri)}&client_id=${Uri.encodeComponent(clientId)}',
    );

    HttpClientResponse response = await request.close();
    String responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode == 200) {
      Map<String, dynamic> jsonResponse = jsonDecode(responseBody);
      String newAccessToken = jsonResponse['access_token'];
      String newRefreshToken = jsonResponse['refresh_token'];

      await storage.write(key: "access_token", value: newAccessToken);
      await storage.write(key: "refresh_token", value: newRefreshToken);

      print('Token refreshed successfully');
      result = true;
    } else {
      print('Failed to refresh token: $responseBody');

      // refresh token probably expired or revoked — trigger re-login
      await login();

      result = false;
    }
    } catch (e) {
    print('Error refreshing token: $e');

    if (openFriendsOnFailure) {
      bool opened = false;
      try {
        opened = await launchUrl(
          Uri.parse('https://my.basic-fit.com/friends?app=true'),
          mode: LaunchMode.inAppBrowserView,
        );
      } catch (_) {
        opened = false;
      }

      if (!opened) {
        result = false;
        // Let the finally block complete the completer and clean up
        throw Exception('Could not open browser.');
      }

      result = false;
    } else {
      result = false;
    }
  } finally {
    httpClient.close();
    if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
      _refreshCompleter!.complete(result);
    }
    _refreshCompleter = null;
  }

  return result;
}

/// Ensures a valid access token is available, refreshing if necessary
Future<String?> getValidAccessToken({bool openFriendsOnFailure = false}) async {
  if (await isTokenExpired()) {
    bool refreshed = await refreshAccessToken(openFriendsOnFailure: openFriendsOnFailure);
    if (!refreshed) return null;
  }
  return await storage.read(key: "access_token");
}

/// Opens the friends page in an in-app browser
Future<void> openFriendsPage() async {
  String? accessToken = await getValidAccessToken(openFriendsOnFailure: true);
  if (accessToken == null) {
    throw Exception('No valid access token available');
  }

  if (!await launchUrl(
    Uri.parse(
      'https://my.basic-fit.com/sso?token=${Uri.encodeComponent(accessToken)}&returl=%2Ffriends%3Fapp%3Dtrue',
    ),
    mode: LaunchMode.inAppBrowserView,
  )) {
    throw Exception('Could not open browser.');
  }
}

/// Logs out by clearing all stored credentials
Future<void> logout() async {
  _lastProcessedCode = null;

  await storage.delete(key: "access_token");
  await storage.delete(key: "refresh_token");
  await storage.delete(key: "device_id");
  await storage.delete(key: "card_number");
  await storage.delete(key: "code_verifier");

  // Update UI state
  await globalAppState?.refreshQrCode();
}
