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
const basicFitUserAgent = 'Basic Fit App/1.100.0.3031 (Android)';

final storage = FlutterSecureStorage();

String? _lastProcessedCode;
String? _activeCodeVerifier;
Completer<bool>? _refreshCompleter;

Future<Map<String, String>> ensureDeviceIds() async {
  var deviceId = await storage.read(key: 'device_id');
  var secureDeviceId = await storage.read(key: 'secure_device_id');

  if (deviceId == null || !RegExp(r'^J[0-9a-f]{36}$').hasMatch(deviceId)) {
    final random = Random.secure();
    deviceId =
        'J${List.generate(36, (_) => random.nextInt(16).toRadixString(16)).join()}';
    await storage.write(key: 'device_id', value: deviceId);
  }

  if (secureDeviceId == null ||
      !RegExp(
        r'^X[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(secureDeviceId)) {
    final bytes = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    );
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int index, [int length = 1]) {
      return bytes
          .sublist(index, index + length)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
    }

    secureDeviceId =
        'X${hex(0, 4)}-${hex(4, 2)}-${hex(6, 2)}-${hex(8, 2)}-${hex(10, 6)}';
    await storage.write(key: 'secure_device_id', value: secureDeviceId);
  }

  return {
    'deviceId': deviceId,
    'secureDeviceId': secureDeviceId,
  };
}

Future<void> setBfaDeviceHeaders(
  HttpClientRequest request, [
  Map<String, String>? deviceIds,
]) async {
  final ids = deviceIds ?? await ensureDeviceIds();
  request.headers.set('Device-Id', ids['deviceId']!);
  request.headers.set('Secure-Device-Id', ids['secureDeviceId']!);
}

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
  await ensureDeviceIds();

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

      if (!await isLoggedIn()) {
        await _fetchMemberInfo(httpClient, accessToken);
      }
    } else {
      globalAppState?.setLoginStatus(LoginStatus.failed);
      throw Exception('Failed to get tokens: $responseBody');
    }
  } finally {
    httpClient.close();
  }
}

Future<bool> _fetchMemberInfo(
  HttpClient httpClient,
  String accessToken,
) async {
  Map<String, dynamic>? secondResponse;

  for (var requestIndex = 0; requestIndex < 2; requestIndex++) {
    final memberInfoRequest = await httpClient.getUrl(
      Uri.parse('https://bfa.basic-fit.com/api/member/info'),
    );
    await setBfaDeviceHeaders(memberInfoRequest);
    memberInfoRequest.headers.set('Authorization', 'Bearer $accessToken');
    memberInfoRequest.headers.set('Bfa-Version', '1.100.0.3031');
    memberInfoRequest.headers.set(
      'User-Agent',
      basicFitUserAgent,
    );
    memberInfoRequest.headers.set('Client-Id', clientId);
    memberInfoRequest.headers.set('Redirect-Uri', redirectUri);

    final memberInfoResponse = await memberInfoRequest.close();
    final memberInfoResponseBody =
        await memberInfoResponse.transform(utf8.decoder).join();
    if (memberInfoResponse.statusCode != 200) {
      globalAppState?.setQrAccessValid(false);
      globalAppState?.setLoginStatus(LoginStatus.failed);
      await globalAppState?.refreshQrCode();
      return false;
    }

    secondResponse = jsonDecode(memberInfoResponseBody) as Map<String, dynamic>;
    final member = secondResponse['member'];
    final memberCardNumber = member is Map
        ? member['cardnumber'] ?? member['cardNumber']
        : null;
    if (memberCardNumber is String && memberCardNumber.isNotEmpty) {
      await storage.write(
        key: "card_number",
        value: memberCardNumber,
      );
    }
  }

  final qrAccessValid = _hasValidQrAccess(secondResponse!);
  globalAppState?.setQrAccessValid(qrAccessValid);

  if (qrAccessValid && await isLoggedIn()) {
    await globalAppState?.refreshQrCode();
  } else {
    if (qrAccessValid) {
      globalAppState?.setLoginStatus(LoginStatus.failed);
    } else {
      await globalAppState?.refreshQrCode();
    }
  }
  return qrAccessValid;
}

bool _hasValidQrAccess(Map<String, dynamic> response) {
  final qrState = response['qrState'];
  if (qrState is! Map) return false;
  return qrState['hasQrAccess'] == true && qrState['shouldSwap'] == false;
}

Future<bool> refreshMemberInfo() async {
  await ensureDeviceIds();
  final accessToken = await storage.read(key: 'access_token');
  if (accessToken == null) return false;

  final httpClient = HttpClient()..userAgent = basicFitUserAgent;
  try {
    return await _fetchMemberInfo(httpClient, accessToken);
  } finally {
    httpClient.close();
  }
}

Future<bool> isLoggedIn() async {
  await ensureDeviceIds();
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
  globalAppState?.setQrAccessValid(true);

  await storage.delete(key: "access_token");
  await storage.delete(key: "refresh_token");
  await storage.delete(key: "card_number");
  await storage.delete(key: "code_verifier");

  // Update UI state
  await globalAppState?.refreshQrCode();
}
