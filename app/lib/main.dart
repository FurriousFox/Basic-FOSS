import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'oauth.dart' as oauth;
import 'qr.dart' as qrutil;

final appLinks = AppLinks();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const App());

  appLinks.uriLinkStream.listen((uri) {
    oauth.code(uri);
  });

  appLinks.getInitialLink().then((uri) async {
    if (uri != null) {
      oauth.code(uri);
    } else {
      if (!await oauth.isLoggedIn()) {
        oauth.login();
      }
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

class AppState extends ChangeNotifier {
  var loggedIn = false;
  QrImageView? qr;

  var _initialized = false;

  Future<void> init({bool timed = false}) async {
    if (_initialized && !timed) return;
    _initialized = true;

    var isLoggedIn = await oauth.isLoggedIn();
    if (isLoggedIn) {
      qr = await qrutil.generateBasicQrCode();
    }
    loggedIn = isLoggedIn;

    notifyListeners();

    if (!timed) {
      Timer.periodic(const Duration(seconds: 5), (_) async {
        await init(timed: true);
      });
    }
  }
}

class Main extends StatelessWidget {
  const Main({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<AppState>();
    appState.init();

    return Scaffold(
      body: Center(
        child: appState.loggedIn
            ? (appState.qr ?? const Text('Generating QR code...'))
            : const Text('Not logged in'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: oauth.login,
        tooltip: 'Login',
        child: const Icon(Icons.login),
      ),
    );
  }
}
