import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'oauth.dart' as oauth;
import 'qr.dart' as qrutil;
import 'wear.dart' as wear;

final appLinks = AppLinks();
AppState? globalAppState;
final Completer<void> appStateReady = Completer<void>();

enum LoginStatus { idle, loggingIn, failed }

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const App());

  appLinks.uriLinkStream.listen((uri) async {
    try {
      await appStateReady.future;
      // Schedule the OAuth code processing to not block the main thread
      Future.microtask(() => oauth.code(uri));
    } catch (e) {
      print('Error processing deep link: $e');
    }
  });

  appLinks.getInitialLink().then((uri) async {
    try {
      await appStateReady.future;
      if (uri != null) {
        // Schedule the OAuth code processing to not block the main thread
        Future.microtask(() => oauth.code(uri));
      } else {
        if (!await oauth.isLoggedIn() && !await wear.WearBridge.isWearDevice) {
          oauth.login();
        }
      }
    } catch (e) {
      print('Error processing initial link: $e');
    }
  });
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AppState(),
      child: MaterialApp(
        title: 'Basic-FOSS',
        theme: ThemeData(colorScheme: ColorScheme.highContrastLight()),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.highContrastDark(surface: Colors.black),
        ),
        home: const Main(),
      ),
    );
  }
}

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  var loggedIn = false;
  var qrAccessValid = true;
  String? qrData;
  LoginStatus loginStatus = LoginStatus.idle;

  var _initialized = false;

  Timer? _pollTimer;
  int _pollGeneration = 0;
  bool _isForeground = true;
  bool _isWearDevice = false;
  bool _deviceTypeKnown = false;
  bool _wearRequestInProgress = false;
  String? _syncedDeviceId;
  String? _syncedCardNumber;

  AppState() {
    globalAppState = this;
    // Observe app lifecycle to pause/resume background polling
    WidgetsBinding.instance.addObserver(this);
    // Default to true: the app starts in the foreground, and no lifecycle
    // change event fires on initial launch (lifecycleState is null).
    // Only resumed is considered foreground; inactive can still be visually
    // present while no longer receiving user input.
    _isForeground = WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused
      && WidgetsBinding.instance.lifecycleState != AppLifecycleState.detached
      && WidgetsBinding.instance.lifecycleState != AppLifecycleState.hidden
      && WidgetsBinding.instance.lifecycleState != AppLifecycleState.inactive;
    if (!appStateReady.isCompleted) {
      appStateReady.complete();
    }
    print('AppState: created, initial foreground=$_isForeground');
  }

  Future<void> init({bool timed = false}) async {
    print('AppState.init called (timed=$timed)');
    if (_initialized && !timed) return;

    var success = false;
    try {
      await oauth.ensureDeviceIds();
      _isWearDevice = await wear.WearBridge.isWearDevice;
      _deviceTypeKnown = true;
      if (!_isForeground) return;
      if (_isWearDevice) {
        final storedData = await wear.WearBridge.getStoredAuthData();
        if (!_isForeground) return;
        _syncedDeviceId = storedData?['deviceId'];
        _syncedCardNumber = storedData?['cardNumber'];
        qrAccessValid =
            storedData?['qrAccessValid']?.toLowerCase() != 'false';
        unawaited(_requestWearState());
      }
      var isLoggedIn = await oauth.isLoggedIn();
      if (!_isForeground) return; // app went to background during await
      if (!_initialized && isLoggedIn) {
        await oauth.refreshMemberInfo();
        if (!_isForeground) return;
      }
      if ((isLoggedIn && qrAccessValid) ||
          (_syncedDeviceId != null && _syncedCardNumber != null)) {
        qrData = await qrutil.generateBasicQrData(
          deviceId: isLoggedIn ? null : _syncedDeviceId,
          cardNumber: isLoggedIn ? null : _syncedCardNumber,
        );
        if (!_isForeground) return; // app went to background during await
      }
      loggedIn = isLoggedIn || (_syncedDeviceId != null && _syncedCardNumber != null);

      notifyListeners();
      unawaited(_updateWearBrightness());
      await _publishPhoneState();

      success = true;
    } catch (e) {
      print('Error in init: $e');
    }

    if (!timed) {
      if (success) {
        _initialized = true;
      }
      if (!_isWearDevice) _startPollTimer();
    }
  }

  Future<void> _publishPhoneState() async {
    if (_isWearDevice || !_isForeground) return;
    final deviceId = await oauth.storage.read(key: 'device_id');
    final secureDeviceId = await oauth.storage.read(key: 'secure_device_id');
    final cardNumber = await oauth.storage.read(key: 'card_number');
    if (!_isForeground) return;
    await wear.WearBridge.publishAuthState(
      loggedIn: loggedIn,
      deviceId: deviceId,
      secureDeviceId: secureDeviceId,
      cardNumber: cardNumber,
      qrAccessValid: qrAccessValid,
    );
  }

  Future<void> _requestWearState() async {
    if (!_isWearDevice || !_isForeground || _wearRequestInProgress) return;
    _wearRequestInProgress = true;
    try {
      await wear.WearBridge.requestAuthState();
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (_isForeground) {
        await refreshQrCode();
      }
    } finally {
      _wearRequestInProgress = false;
    }
  }

  void _startPollTimer() {
    _stopPollTimer();
    if (!_isForeground) {
      print('PollTimer: not starting because app is not foreground');
      return;
    }
    // _stopPollTimer() already bumped the generation, so capture the
    // current value — any older in-flight callback is already invalid.
    final int gen = _pollGeneration;
    const interval = Duration(seconds: 5);
    void scheduleNext() {
      if (gen != _pollGeneration) {
        print('PollTimer: stale generation ($gen != $_pollGeneration), not rescheduling');
        return;
      }
      if (!_isForeground) {
        print('PollTimer: not scheduling next because app not foreground');
        return;
      }
      print('PollTimer: scheduling one-shot (5s) [gen=$gen]');
      _pollTimer = Timer(interval, () async {
        if (gen != _pollGeneration || !_isForeground) {
          print('PollTimer: fired but stale/backgrounded, skipping [gen=$gen, current=$_pollGeneration, fg=$_isForeground]');
          return;
        }
        print('PollTimer: fired — calling init(timed: true) [gen=$gen]');
        await init(timed: true);
        scheduleNext();
      });
    }

    scheduleNext();
  }

  void _stopPollTimer() {
    if (_pollTimer != null) {
      print('PollTimer: stopping');
    }
    _pollTimer?.cancel();
    _pollTimer = null;
    // Invalidate any in-flight async callbacks from the previous chain
    _pollGeneration++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('Lifecycle: didChangeAppLifecycleState -> $state');
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      if (!_deviceTypeKnown) {
        return;
      } else if (_isWearDevice) {
        unawaited(_requestWearState());
      } else {
        Future.microtask(() => refreshQrCode());
        _startPollTimer();
      }
    } else {
      _isForeground = false;
      _stopPollTimer();
      unawaited(_restoreWearBrightness());
    }
  }

  @override
  void dispose() {
    print('AppState: dispose');
    _isForeground = false;
    WidgetsBinding.instance.removeObserver(this);
    _stopPollTimer();
    unawaited(_restoreWearBrightness());
    super.dispose();
  }

  Future<void> refreshQrCode() async {
    print('AppState.refreshQrCode called');
    if (!_isForeground) return;
    try {
      var isLoggedIn = await oauth.isLoggedIn();
      if (!_isForeground) return; // app went to background during await
      if (isLoggedIn) {
        qrData = qrAccessValid
            ? await qrutil.generateBasicQrData()
            : null;
        if (!_isForeground) return; // app went to background during await
        print('refreshQrCode: updated qrData length=${qrData?.length ?? 0}');
        loginStatus = LoginStatus.idle;
      } else {
        qrData = null;
      }
      if (!isLoggedIn && _isWearDevice) {
        final storedData = await wear.WearBridge.getStoredAuthData();
        if (!_isForeground) return;
        _syncedDeviceId = storedData?['deviceId'];
        _syncedCardNumber = storedData?['cardNumber'];
        qrAccessValid =
            storedData?['qrAccessValid']?.toLowerCase() != 'false';
        if (_syncedDeviceId != null && _syncedCardNumber != null) {
          loggedIn = true;
          qrData = qrAccessValid
              ? await qrutil.generateBasicQrData(
                  deviceId: _syncedDeviceId,
                  cardNumber: _syncedCardNumber,
                )
              : null;
        }
      }
      if (isLoggedIn) {
        loggedIn = true;
      } else if (_syncedDeviceId == null || _syncedCardNumber == null) {
        loggedIn = false;
      }
      notifyListeners();
      unawaited(_updateWearBrightness());
      await _publishPhoneState();
    } catch (e) {
      print('Error in refreshQrCode: $e');
    }
  }

  Future<void> _updateWearBrightness() async {
    if (_isWearDevice && _isForeground && loggedIn && qrData != null) {
      await wear.WearBridge.setMaxBrightness();
    } else {
      await _restoreWearBrightness();
    }
  }

  Future<void> _restoreWearBrightness() async {
    if (_isWearDevice) {
      await wear.WearBridge.restoreBrightness();
    }
  }

  void setLoginStatus(LoginStatus status) {
    loginStatus = status;
    notifyListeners();
  }

  void setQrAccessValid(bool valid) {
    qrAccessValid = valid;
    if (!valid) {
      qrData = null;
    }
    notifyListeners();
  }
}

class Main extends StatefulWidget {
  const Main({super.key});

  @override
  State<Main> createState() => _MainState();
}

class _MainState extends State<Main> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<AppState>();

    String getStatusText() {
      switch (appState.loginStatus) {
        case LoginStatus.loggingIn:
          return 'Logging in...';
        case LoginStatus.failed:
          return 'Login failed';
        case LoginStatus.idle:
          return 'Not logged in';
      }
    }

    final orangeQrAccessFallback =
        appState.loggedIn && !appState.qrAccessValid;

    return Scaffold(
      backgroundColor: orangeQrAccessFallback
          ? Colors.orange
          : null,
      body: SafeArea(
        child: Center(
          child: appState.loggedIn
          ? (appState.qrData != null
            ? QrImageView(
              data: appState.qrData!,
              size: math.min(
                MediaQuery.sizeOf(context).shortestSide * 0.78,
                360,
              ),
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              backgroundColor: orangeQrAccessFallback
                  ? Colors.orange
                  : Colors.white,
              dataModuleStyle: QrDataModuleStyle(
                color: Colors.black,
                dataModuleShape: QrDataModuleShape.square,
              ),
              eyeStyle: QrEyeStyle(
                color: Colors.black,
                eyeShape: QrEyeShape.square,
              ),
              )
            : const Text('Generating QR code...'))
          : Text(
              appState._isWearDevice
                  ? 'Login on phone'
                  : getStatusText(),
            ),
        ),
      ),
      floatingActionButton: !appState._deviceTypeKnown ||
              (appState._isWearDevice && appState.loggedIn)
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (appState.loggedIn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: FloatingActionButton(
                      onPressed: oauth.openFriendsPage,
                      tooltip: 'Friends',
                      child: const Icon(Icons.people),
                    ),
                  ),
                FloatingActionButton(
                  onPressed: appState.loggedIn
                      ? oauth.logout
                      : appState._isWearDevice
                          ? wear.WearBridge.requestAuthState
                          : oauth.login,
                  tooltip: appState.loggedIn
                      ? 'Logout'
                      : 'Login',
                  child: Icon(
                    appState.loggedIn
                        ? Icons.logout
                        : Icons.login,
                  ),
                ),
              ],
            ),
    );
  }
}
