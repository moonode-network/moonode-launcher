/*
 * Moonode Launcher
 * Copyright (C) 2026 Moonode
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

class _MoonodeLauncherState extends State<MoonodeLauncher> with WidgetsBindingObserver {
  late final WebViewController _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _initialLoadComplete = false;
  bool _isOffline = false;
  String _appVersion = '';
  bool _isSettingsOpen = false;

  // Moonode TV URL - the main content
  static const String moonodeTvUrl = 'https://moonode.tv';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAppVersion();
    _checkConnectivity();
    _initWebView();
    _registerNativeKeyHandler();
    _refreshHijackStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check the HOME Guardian whenever Moonode comes back to the foreground
    // - the most likely time it was just disabled by Fire OS / an APK reinstall.
    if (state == AppLifecycleState.resumed) {
      _refreshHijackStatus();
    }
  }

  /// On Fire TV, silently re-enable the HOME Guardian accessibility service
  /// if Fire OS has disabled it. This works because the deployment script
  /// (setup-moonode-launcher.sh) ADB-grants WRITE_SECURE_SETTINGS so the
  /// launcher can self-heal without any user interaction. If the permission
  /// was never granted (e.g. someone sideloaded the APK without the script),
  /// this silently no-ops - HOME just won't bounce, but Moonode keeps working.
  Future<void> _refreshHijackStatus() async {
    try {
      final info = await widget.launcherChannel.getDeviceInfo();
      final isFireTv = info['isFireTv'] == true;
      if (!isFireTv) return;
      final enabled = await widget.launcherChannel.isHomeHijackEnabled();
      if (enabled) return;
      await widget.launcherChannel.enableHomeHijackService();
    } catch (_) {
      // Older builds without the channel methods: nothing to do.
    }
  }

  void _registerNativeKeyHandler() {
    widget.launcherChannel.setKeyEventHandler(
      onOpenSettings: _openSettings,
      onOpenAndroidSettings: _openAndroidSettings,
      onGoHome: _goHome,
    );
  }

  void _goHome() {
    if (_isSettingsOpen) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      _isSettingsOpen = false;
    }
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
      // Native screen-rotation bridge intentionally NOT wired up: Fire OS does
      // not honour setRequestedOrientation(PORTRAIT) by rotating the display;
      // it letterboxes the activity into a portrait-shaped sub-window of the
      // landscape panel, leaving SurfaceViews (video) full-screen landscape.
      // Result is worse than CSS rotation: HTML rendered in a 607x1080 box
      // with two black bars, with video bleeding through across the full
      // 1920x1080. We keep the activity locked to landscape and let the web
      // player handle rotation via CSS transforms instead. (The Kotlin
      // setScreenOrientation method stays in place but unreachable from JS;
      // it is harmless and lets us re-enable the bridge selectively in the
      // future if Fire OS behaviour changes or for non-Fire-TV devices.)
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

            // Inject viewport fix + render-process-gone auto-recovery early.
            //
            // Background: Fire TV Stick (1st gen) has only ~921 MB total RAM.
            // Chromium's sandboxed renderer for this WebView runs at ~265 MB
            // and when the system runs out of memory the lowmemorykiller will
            // kill it as `fore TOP`. The WebView restarts itself but lands
            // back on the moonode.tv root URL, looking to the user like the
            // launcher just rebooted.
            //
            // To make recovery invisible: we keep `moonode_last_screen` in
            // localStorage (Service Worker survives the restart, so does its
            // localStorage). On every page start, if we just landed on root
            // BUT we have a recent screen-id stashed, jump straight to it
            // with replace() so the splash doesn't show and history isn't
            // polluted.
            _webViewController.runJavaScript('''
              (function(){
                try {
                  var meta = document.createElement('meta');
                  meta.name = 'viewport';
                  meta.content = 'width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no';
                  if (document.head) document.head.appendChild(meta);
                } catch(_) {}

                try {
                  var path = window.location.pathname || '';
                  var isRoot = path === '/' || path === '' || path === '/index.html';
                  if (isRoot) {
                    var raw = window.localStorage && window.localStorage.getItem('moonode_last_screen');
                    if (raw) {
                      var saved = JSON.parse(raw);
                      var ageMs = Date.now() - (saved.savedAt || 0);
                      // Only auto-rejoin if the stash is fresh (< 6h) so we
                      // don't permanently pin a stale screen-id from days ago.
                      if (saved.id && ageMs < 6 * 60 * 60 * 1000) {
                        window.location.replace('/' + saved.id);
                      }
                    }
                  } else {
                    // We're on a real screen - persist it for next recovery.
                    var id = path.replace(/^\\//, '').split(/[\\/?#]/)[0];
                    if (id) {
                      window.localStorage.setItem(
                        'moonode_last_screen',
                        JSON.stringify({ id: id, savedAt: Date.now() })
                      );
                    }
                  }
                } catch(_) {}
              })();
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
            
            // Save current URL for offline recovery + cold-start auto-recovery.
            // The timestamp is used by `_resolveStartupUrl()` to decide whether
            // a cached screen-id is still fresh enough to deep-link into when
            // a brand-new process spawns (after a memory kill, reboot, etc).
            if (url.contains('/') && url != moonodeTvUrl) {
              final uri = Uri.parse(url);
              if (uri.pathSegments.isNotEmpty) {
                widget.sharedPreferences.setString('cached_screen_id', uri.pathSegments.first);
                widget.sharedPreferences.setInt(
                  'cached_screen_id_at',
                  DateTime.now().millisecondsSinceEpoch,
                );
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

    // Cold-start recovery: on Fire TV Stick (~921 MB RAM) the OS routinely
    // kills our entire foreground process under memory pressure. When the
    // system relaunches us via the HOME intent, we land here in a brand-new
    // process. If we just blindly load `moonode.tv` root, the user sees a
    // visible "reload" back to the home/splash. Instead, if we have a recent
    // screen-id stashed from a prior session, jump straight to that URL.
    //
    // The 6h freshness window matches the JS-side localStorage check so the
    // two recovery paths agree on what counts as "still relevant".
    final initialUrl = _resolveStartupUrl();
    _webViewController.loadRequest(Uri.parse(initialUrl));
  }

  /// Pick the URL to load on launcher start. Defaults to moonode.tv root, but
  /// if a recent screen-id is cached we jump directly there to make process
  /// kill recovery invisible to the user.
  String _resolveStartupUrl() {
    try {
      final cachedId = widget.sharedPreferences.getString('cached_screen_id');
      final savedAtMs = widget.sharedPreferences.getInt('cached_screen_id_at') ?? 0;
      if (cachedId != null && cachedId.isNotEmpty) {
        final ageMs = DateTime.now().millisecondsSinceEpoch - savedAtMs;
        // 6h freshness window - long enough to survive overnight standby,
        // short enough that a stale screen-id doesn't pin a customer to an
        // outdated playlist forever after they've moved the device.
        if (savedAtMs > 0 && ageMs < 6 * 60 * 60 * 1000) {
          return '$moonodeTvUrl/$cachedId';
        }
      }
    } catch (_) {}
    return moonodeTvUrl;
  }

  void _openSettings() {
    if (_isSettingsOpen) return;
    _isSettingsOpen = true;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          launcherChannel: widget.launcherChannel,
          sharedPreferences: widget.sharedPreferences,
        ),
      ),
    ).then((_) {
      _isSettingsOpen = false;
    });
  }

  /// Open Android System Settings directly (escape hatch if launcher fails)
  void _openAndroidSettings() {
    widget.launcherChannel.openSettings();
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
          if (event is KeyDownEvent) {
            // Open launcher settings on Menu/F1 button press
            if (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                event.logicalKey == LogicalKeyboardKey.f1 ||
                event.logicalKey == LogicalKeyboardKey.settings) {
              _openSettings();
            }
            // ESCAPE HATCH: Open Android Settings on F2 or Escape key
            // This allows recovery even if screen is black/stuck
            if (event.logicalKey == LogicalKeyboardKey.f2 ||
                event.logicalKey == LogicalKeyboardKey.escape) {
              _openAndroidSettings();
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: _openSettings,
                            icon: const Icon(Icons.apps, size: 18),
                            label: const Text('Launcher Settings'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF4FB3FF),
                            ),
                          ),
                          const SizedBox(width: 24),
                          TextButton.icon(
                            onPressed: _openAndroidSettings,
                            icon: const Icon(Icons.settings, size: 18),
                            label: const Text('Android Settings'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFFF6B6B),
                            ),
                          ),
                        ],
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

