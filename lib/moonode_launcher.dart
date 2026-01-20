/*
 * Moonode Launcher
 * Copyright (C) 2025 Moonode
 *
 * Main launcher widget - displays moonode.tv in fullscreen WebView
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'launcher_channel.dart';
import 'settings_screen.dart';

class MoonodeLauncher extends StatefulWidget {
  final SharedPreferences sharedPreferences;
  final LauncherChannel launcherChannel;

  const MoonodeLauncher({
    super.key,
    required this.sharedPreferences,
    required this.launcherChannel,
  });

  @override
  State<MoonodeLauncher> createState() => _MoonodeLauncherState();
}

class _MoonodeLauncherState extends State<MoonodeLauncher> {
  late final WebViewController _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // Moonode TV URL - the main content
  static const String moonodeTvUrl = 'https://moonode.tv';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            // Inject JavaScript to enable audio context (workaround for some devices)
            _webViewController.runJavaScript('''
              // Auto-resume AudioContext if suspended (Chromium policy workaround)
              if (typeof AudioContext !== 'undefined') {
                const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
                if (audioCtx.state === 'suspended') {
                  audioCtx.resume();
                }
              }
              // Enable video autoplay
              document.querySelectorAll('video').forEach(v => {
                v.muted = false;
                v.play().catch(() => {});
              });
            ''');
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
              _hasError = true;
              _errorMessage = error.description;
            });
          },
        ),
      );
    
    // ==========================================
    // ANDROID SPECIFIC: Enable media autoplay
    // This fixes the Chromium autoplay policy!
    // ==========================================
    final platform = _webViewController.platform;
    if (platform is AndroidWebViewController) {
      // Allow media playback without user gesture (THE KEY FIX!)
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    
    // Load moonode.tv
    _webViewController.loadRequest(Uri.parse(moonodeTvUrl));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          launcherChannel: widget.launcherChannel,
          sharedPreferences: widget.sharedPreferences,
        ),
      ),
    );
  }

  void _retryLoading() {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    _webViewController.loadRequest(Uri.parse(moonodeTvUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: (KeyEvent event) {
          // Open settings on Menu button press
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                event.logicalKey == LogicalKeyboardKey.f1 ||
                event.logicalKey == LogicalKeyboardKey.settings) {
              _openSettings();
            }
          }
        },
        child: Stack(
          children: [
            // WebView with moonode.tv
            WebViewWidget(controller: _webViewController),

            // Loading indicator
            if (_isLoading)
              Container(
                color: const Color(0xFF0A0E17),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Moonode Logo
                      Image.asset(
                        'assets/logo.png',
                        width: 150,
                        height: 150,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.brightness_2,
                          size: 80,
                          color: Color(0xFFF5D742),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Moonode Launcher',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF5D742)),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Connecting to your community...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Error screen with retry
            if (_hasError && !_isLoading)
              Container(
                color: const Color(0xFF0A0E17),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/logo.png',
                        width: 100,
                        height: 100,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.wifi_off,
                          size: 80,
                          color: Color(0xFFF5D742),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Connection Issue',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage.isNotEmpty 
                            ? _errorMessage 
                            : 'Unable to connect to moonode.tv',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Offline mode will display cached content',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: _retryLoading,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5D742),
                          foregroundColor: const Color(0xFF0A0E17),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text(
                          'Retry',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _openSettings,
                        child: const Text(
                          'Open Settings',
                          style: TextStyle(color: Color(0xFF4FB3FF)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

