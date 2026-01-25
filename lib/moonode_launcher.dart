/*
 * Moonode Launcher
 * Copyright (C) 2025 Moonode
 *
 * Main launcher widget - displays moonode.tv in fullscreen WebView
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
  bool _initialLoadComplete = false;
  bool _isOffline = false;
  String _appVersion = '';

  // Moonode TV URL - the main content
  static const String moonodeTvUrl = 'https://moonode.tv';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _checkConnectivity();
    _initWebView();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = 'v${packageInfo.version}+${packageInfo.buildNumber}';
    });
  }

  Future<void> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      // connectivity_plus returns a List now
      _isOffline = connectivityResult.contains(ConnectivityResult.none) || 
                   connectivityResult.isEmpty;
    });
    
    // Listen for connectivity changes
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final wasOffline = _isOffline;
      setState(() {
        _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
      });
      // Auto-reload when coming back online after an error
      if (wasOffline && !_isOffline && _hasError) {
        _retryLoading();
      }
    });
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF)) // White background to match moonode.tv
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            // Only show loading indicator for initial load, not internal navigations
            if (!_initialLoadComplete) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
            
            // Inject viewport fix early to prevent zoom flash
            _webViewController.runJavaScript('''
              var meta = document.createElement('meta');
              meta.name = 'viewport';
              meta.content = 'width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no';
              if (document.head) document.head.appendChild(meta);
            ''');
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _initialLoadComplete = true;
              // IMPORTANT: Clear error state - Service Worker may have served cached content!
              // If we reached onPageFinished, the page loaded successfully (from cache or network)
              _hasError = false;
              _errorMessage = '';
            });
            
            // Save current URL for offline recovery
            if (url.contains('/') && url != moonodeTvUrl) {
              // Extract screen ID from URL like moonode.tv/abc123
              final uri = Uri.parse(url);
              if (uri.pathSegments.isNotEmpty) {
                widget.sharedPreferences.setString('cached_screen_id', uri.pathSegments.first);
              }
            }
            
            // Inject JavaScript to enable audio context and fix viewport
            _webViewController.runJavaScript('''
              // Fix viewport scale - ensure page fits screen properly
              (function() {
                // Remove any existing viewport meta
                var existing = document.querySelector('meta[name="viewport"]');
                if (existing) existing.remove();
                
                // Create proper viewport for TV screens
                var meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = 'width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no';
                document.head.appendChild(meta);
                
                // Reset any CSS transforms/scales
                document.documentElement.style.transform = 'none';
                document.documentElement.style.zoom = '1';
                document.body.style.transform = 'none';
                document.body.style.zoom = '1';
                document.body.style.minHeight = '100vh';
                document.body.style.width = '100%';
                document.body.style.overflow = 'hidden';
              })();
              
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
              // Notify app that page loaded (for debugging)
              console.log('[MoonodeLauncher] Page loaded: ' + window.location.href);
            ''');
          },
          onWebResourceError: (WebResourceError error) {
            // IMPORTANT: Only show error for MAIN FRAME failures
            // The Service Worker may still serve cached content!
            // Subresource errors (images, scripts, API calls) should be ignored.
            if (error.isForMainFrame ?? false) {
              // Give the Service Worker time to respond from cache
              // Only show error if this is truly a failure (no cached content)
              Future.delayed(const Duration(seconds: 2), () {
                // Check if page actually loaded (Service Worker might have served cached content)
                _webViewController.currentUrl().then((currentUrl) {
                  // If we're still on the original URL or about:blank, show error
                  // If URL changed (e.g., to /screenId), page loaded from cache
                  if (currentUrl == null || 
                      currentUrl == 'about:blank' || 
                      currentUrl == moonodeTvUrl) {
                    setState(() {
                      _isLoading = false;
                      _hasError = true;
                      _errorMessage = error.description;
                    });
                  }
                });
              });
            }
          },
        ),
      );
    
    // ==========================================
    // ANDROID SPECIFIC: Enable offline caching & media
    // ==========================================
    final platform = _webViewController.platform;
    if (platform is AndroidWebViewController) {
      // Allow media playback without user gesture
      platform.setMediaPlaybackRequiresUserGesture(false);
      
      // Fix zoom/scale issues - set text zoom to 100% (no scaling)
      platform.setTextZoom(100);
      
      // Enable wide viewport mode (fits content to screen width)
      // This helps prevent the "zoomed in" appearance
    }
    
    // Enable JavaScript and set user agent to indicate launcher mode
    _webViewController.setUserAgent(
      'Mozilla/5.0 (Linux; Android TV; Moonode Launcher) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    );
    
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
    
    // If offline, try loading cached screen directly
    if (_isOffline) {
      final cachedScreenId = widget.sharedPreferences.getString('cached_screen_id');
      if (cachedScreenId != null && cachedScreenId.isNotEmpty) {
        // Load the cached screen URL - Service Worker should serve from cache
        _webViewController.loadRequest(Uri.parse('$moonodeTvUrl/$cachedScreenId'));
        return;
      }
    }
    
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
                child: Stack(
                  children: [
                    // Centered content
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Moonode Logo - 50% bigger, precached
                          Image.asset(
                            'assets/logo.png',
                            width: 225,
                            height: 225,
                            cacheWidth: 450, // Precache at 2x for faster display
                            cacheHeight: 450,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.brightness_2,
                              size: 120,
                              color: Color(0xFFF5D742),
                            ),
                          ),
                          const SizedBox(height: 32),
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF5D742)),
                          ),
                        ],
                      ),
                    ),
                    // Version indicator - bottom right
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Text(
                        _appVersion,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white38,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Error screen with retry
            if (_hasError && !_isLoading)
              Container(
                color: const Color(0xFF0A0E17),
                child: Stack(
                  children: [
                    Center(
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
                    // Version indicator - bottom right
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Text(
                        _appVersion,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white38,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

