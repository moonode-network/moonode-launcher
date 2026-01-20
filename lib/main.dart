/*
 * Moonode Launcher
 * Copyright (C) 2025 Moonode
 *
 * The smart launcher for Moonode TV screens
 * Connecting organizations to their communities
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'moonode_launcher.dart';
import 'launcher_channel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock to landscape orientation for TV
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  // Hide system UI for immersive experience
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );

  final sharedPreferences = await SharedPreferences.getInstance();
  final launcherChannel = LauncherChannel();

  runApp(MoonodeLauncherApp(
    sharedPreferences: sharedPreferences,
    launcherChannel: launcherChannel,
  ));
}

class MoonodeLauncherApp extends StatelessWidget {
  final SharedPreferences sharedPreferences;
  final LauncherChannel launcherChannel;

  // Moonode Brand Colors
  static const Color moonodeYellow = Color(0xFFF5D742);
  static const Color midnightBlue = Color(0xFF0A0E17);
  static const Color midnightLight = Color(0xFF1A1F2E);
  static const Color skyBlue = Color(0xFF4FB3FF);

  const MoonodeLauncherApp({
    super.key,
    required this.sharedPreferences,
    required this.launcherChannel,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moonode Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: moonodeYellow,
        scaffoldBackgroundColor: midnightBlue,
        colorScheme: const ColorScheme.dark(
          primary: moonodeYellow,
          secondary: skyBlue,
          surface: midnightLight,
          background: midnightBlue,
        ),
        fontFamily: 'Roboto',
      ),
      home: MoonodeLauncher(
        sharedPreferences: sharedPreferences,
        launcherChannel: launcherChannel,
      ),
    );
  }
}
