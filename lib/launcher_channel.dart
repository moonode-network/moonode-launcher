/*
 * Moonode Launcher
 * Copyright (C) 2026 Moonode
 *
 * Platform channel for native Android communication
 */

import 'package:flutter/services.dart';

class LauncherChannel {
  static const MethodChannel _methodChannel = MethodChannel('com.moonode.launcher/method');
  static const MethodChannel _keyEventChannel = MethodChannel('com.moonode.launcher/keyEvent');
  static const EventChannel _eventChannel = EventChannel('com.moonode.launcher/event');

  /// Register a callback for native key events intercepted before the WebView.
  /// [onOpenSettings] fires on Menu/F1/Settings remote buttons.
  /// [onOpenAndroidSettings] fires on F2.
  void setKeyEventHandler({
    required VoidCallback onOpenSettings,
    required VoidCallback onOpenAndroidSettings,
    required VoidCallback onGoHome,
  }) {
    _keyEventChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openSettings':
          onOpenSettings();
          break;
        case 'openAndroidSettings':
          onOpenAndroidSettings();
          break;
        case 'goHome':
          onGoHome();
          break;
      }
    });
  }

  /// Get list of installed applications
  Future<List<Map<String, dynamic>>> getApplications() async {
    final List<dynamic> apps = await _methodChannel.invokeMethod('getApplications');
    return apps.cast<Map<String, dynamic>>();
  }

  /// Launch an app by package name
  Future<bool> launchApp(String packageName) async {
    return await _methodChannel.invokeMethod('launchApp', packageName);
  }

  /// Launch Moonode TV App specifically
  Future<bool> launchMoonodeApp() async {
    return await _methodChannel.invokeMethod('launchMoonodeApp');
  }

  /// Open Android Settings
  Future<bool> openSettings() async {
    return await _methodChannel.invokeMethod('openSettings');
  }

  /// Open app info for a specific package
  Future<bool> openAppInfo(String packageName) async {
    return await _methodChannel.invokeMethod('openAppInfo', packageName);
  }

  /// Uninstall an app
  Future<bool> uninstallApp(String packageName) async {
    return await _methodChannel.invokeMethod('uninstallApp', packageName);
  }

  /// Check if this launcher is set as default
  Future<bool> isDefaultLauncher() async {
    return await _methodChannel.invokeMethod('isDefaultLauncher');
  }

  /// Open the system "Choose default launcher" UI so the user can switch
  /// HOME to another launcher (recovery path if Moonode misbehaves).
  ///
  /// On Android TV / AOSP this opens the HOME settings picker.
  /// On Fire TV (which doesn't expose a HOME picker) this falls back to
  /// the Moonode app-info screen where the user can clear defaults or
  /// uninstall to return to the Amazon launcher.
  Future<bool> chooseDefaultLauncher() async {
    return await _methodChannel.invokeMethod('chooseDefaultLauncher');
  }

  /// Returns device info used to adapt the UI (e.g. Fire TV recovery hints).
  /// Keys: manufacturer, brand, model, sdkInt, isFireTv, isAndroidTv.
  Future<Map<String, dynamic>> getDeviceInfo() async {
    final result = await _methodChannel.invokeMethod('getDeviceInfo');
    return Map<String, dynamic>.from(result as Map);
  }

  /// Stream of package change events
  Stream<Map<String, dynamic>> get packageEvents {
    return _eventChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    });
  }
}

