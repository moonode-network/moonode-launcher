/*
 * Moonode Launcher
 * Copyright (C) 2026 Moonode
 *
 * Main launcher widget - displays moonode.tv in fullscreen WebView
 */

import 'dart:async';

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

  // Human-readable status surfaced under the spinner during the
  // pre-WebView wait (Wi-Fi association, initial connectivity probe, etc.).
  // Updating this gives the operator visible proof the launcher is making
  // progress instead of staring at a generic "loading…" screen, and gives
  // us a free in-the-field diagnostic: a screenshot of the splash tells us
  // exactly which phase we hung in.
  String _loadingStatus = 'Starting up…';

  void _setStatus(String s) {
    if (!mounted) return;
    if (_loadingStatus == s) return;
    setState(() => _loadingStatus = s);
  }

  // Single, long-lived FocusNode for the KeyboardListener.
  //
  // Previous behaviour was `focusNode: FocusNode()..requestFocus()` inside
  // build(), which allocated a brand-new FocusNode AND stole focus on every
  // setState (loading toggle, error toggle, version-string update, app
  // resume). Each FocusNode holds native input wiring; leaking one per
  // rebuild also caused intermittent focus thrash where keyboard events
  // briefly stopped routing to the new node mid-frame. Caching it here
  // and disposing it in dispose() is the canonical Flutter pattern.
  late final FocusNode _keyboardFocusNode;

  // Moonode TV URL - the main content
  static const String moonodeTvUrl = 'https://moonode.tv';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keyboardFocusNode = FocusNode(debugLabel: 'MoonodeLauncher.keyboard');
    // One-shot focus request after the first frame. We can't request focus
    // here in initState because the FocusNode isn't attached to the tree
    // yet; doing it in build() risks re-requesting focus on every rebuild
    // (the previous black-screen regression). Scheduling it once via
    // addPostFrameCallback gives the same UX as the old inline
    // `..requestFocus()` without the leak or the rebuild loop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
    _loadAppVersion();
    _checkConnectivity();
    _initWebView();
    _registerNativeKeyHandler();
    _refreshHijackStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardFocusNode.dispose();
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
              _setStatus('Loading moonode.tv…');
            }

            // Inject the viewport meta as early as possible so the page can
            // never render at the wrong scale on TV panels. Auto-rejoin /
            // deep-link recovery used to live here too, but it was removed
            // — moonode.tv handles paired-screen redirects itself via
            // localStorage["45%643D"] in pages/generic.
            _webViewController.runJavaScript('''
              (function(){
                try {
                  var meta = document.createElement('meta');
                  meta.name = 'viewport';
                  meta.content = 'width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no';
                  if (document.head) document.head.appendChild(meta);
                } catch(_) {}

                // Native-side deep-link auto-rejoin was REMOVED on purpose:
                // moonode.tv already owns the unpaired -> paired redirect via
                // the localStorage["45%643D"] -> window.location.replace path
                // in pages/generic. Re-doing it here just hides what is
                // happening on the web side (and, at one point, masked a real
                // bug where the launcher stored only the first path segment
                // and deep-linked to a non-existent route). Letting moonode.tv
                // perform the redirect itself keeps Fire TV, Android TV and
                // Xiaomi MiTV on the exact same flow and makes failures
                // visible (you see the pairing digit flash, then the
                // redirect) instead of silently swallowed by the launcher.
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
            
            // Diagnostic-only: record the last URL the WebView landed on so
            // we can answer "what screen was this device on before the
            // reboot/crash?" from logcat (see MoonodePersist fingerprint
            // in MainActivity.kt). We do NOT use these values for any
            // startup redirect — that decision belongs to moonode.tv.
            if (url.contains('/') && url != moonodeTvUrl) {
              final uri = Uri.parse(url);
              if (uri.pathSegments.isNotEmpty) {
                final fullPath = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
                widget.sharedPreferences.setString('cached_screen_path', fullPath);
                widget.sharedPreferences.setInt(
                  'cached_screen_id_at',
                  DateTime.now().millisecondsSinceEpoch,
                );
                widget.sharedPreferences.setString(
                  'cached_screen_id',
                  uri.pathSegments.first,
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

    // Defer the actual navigation until either (a) we've observed a real
    // network connection, or (b) we've waited long enough that doing
    // nothing would feel broken. See `_loadInitialUrlWhenReady()` for
    // the full reasoning. The Flutter splash (logo + spinner) is already
    // visible at this point, so the wait is invisible to the operator.
    _loadInitialUrlWhenReady();
  }

  /// Wait briefly for Wi-Fi to associate before pointing the WebView at
  /// `moonode.tv`. Falls back to loading anyway after a hard ceiling so a
  /// truly offline device still gets the SW/cache flow.
  ///
  /// Why this exists
  /// ---------------
  /// Without the wait, the boot sequence is:
  ///
  ///   1. Activity onCreate -> WebView created -> loadRequest(moonode.tv)
  ///   2. WebView fires the request *before* the Wi-Fi state machine has
  ///      finished associating (very common on Xiaomi MiTV: the panel/SoC
  ///      finishes booting in ~3 s; the Wi-Fi driver settles in ~5–8 s).
  ///   3. axios.get() in pages/generic throws ECONNRESET / TIMEOUT.
  ///   4. setDigits() catch block reads localStorage["45%643D"] and
  ///      window.location.replace's to the *previously paired* screen.
  ///
  /// That is correct behaviour for an offline reboot (operator just wants
  /// their signage back). It is *wrong* when the operator has revoked the
  /// pairing on the dashboard: the device still flashes the old paired
  /// screen because the offline fallback fires before the API ever gets
  /// a chance to say "this code is no longer active". Operator can't
  /// re-pair without manually clearing app data.
  ///
  /// With the wait:
  ///
  ///   - online at boot                       -> loads immediately, normal flow
  ///   - online after Wi-Fi associates (~3 s) -> loads after Wi-Fi is up,
  ///                                             API call succeeds, dashboard
  ///                                             revocation is honoured
  ///   - offline (true)                       -> loads after the cap, SW + the
  ///                                             setDigits() catch path provide
  ///                                             the cached redirect exactly as
  ///                                             before
  ///
  /// The cap is intentionally generous (10 s). Most Wi-Fi stacks resolve
  /// well under 5 s; the extra headroom protects against laggy MIUI builds
  /// without making truly-offline boots feel broken.
  Future<void> _loadInitialUrlWhenReady() async {
    const maxWaitMs = 10000;
    bool loaded = false;
    StreamSubscription<List<ConnectivityResult>>? sub;

    void doLoad(String reason) {
      if (loaded || !mounted) return;
      loaded = true;
      sub?.cancel();
      debugPrint('[MoonodeLauncher] initial load via $reason');
      // Final pre-WebView status. Stays visible until pages/generic
      // either redirects (cached or via API) or paints its own pairing
      // UI; either way our onPageFinished hook clears _isLoading.
      _setStatus(
        reason == 'timeout'
            ? 'Loading Moonode (offline mode)…'
            : 'Loading Moonode…',
      );
      _webViewController.loadRequest(Uri.parse(moonodeTvUrl));
    }

    _setStatus('Checking network…');

    // Belt-and-suspenders ceiling. If the connectivity plugin hangs, errors
    // out, or never reports an online state (rare but seen in the wild on
    // misconfigured Xiaomi Wi-Fi state machines), we still navigate the
    // WebView so the operator never stares at the splash forever.
    Future.delayed(const Duration(milliseconds: maxWaitMs),
        () => doLoad('timeout'));

    try {
      final initial = await Connectivity().checkConnectivity();
      final initiallyOnline =
          initial.isNotEmpty && !initial.contains(ConnectivityResult.none);
      if (initiallyOnline) {
        doLoad('initial-online');
        return;
      }
      _setStatus('Waiting for Wi-Fi…');
      sub = Connectivity().onConnectivityChanged.listen((results) {
        final online =
            results.isNotEmpty && !results.contains(ConnectivityResult.none);
        if (online) doLoad('connectivity-event');
      });
    } catch (e) {
      // Connectivity plugin failure - don't gate the launcher on it.
      debugPrint('[MoonodeLauncher] connectivity check failed: $e');
      doLoad('connectivity-error');
    }
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
    
    // Always retry against moonode.tv root and let the web app's own
    // unpaired -> paired redirect logic take over. When offline,
    // `setDigits()` in pages/generic catches the network error and
    // window.location.replace's via the cached localStorage["45%643D"];
    // when online and paired, it redirects via the API response. Either
    // way the launcher does not need to second-guess the URL.
    _webViewController.loadRequest(Uri.parse(moonodeTvUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: KeyboardListener(
        focusNode: _keyboardFocusNode,
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
                          const SizedBox(height: 20),
                          // Phase status. Updated by _setStatus() during the
                          // pre-WebView wait (Starting up / Checking network /
                          // Waiting for Wi-Fi / Loading Moonode), then by the
                          // WebView's onPageStarted hook ("Loading
                          // moonode.tv…"). Animated so the change reads as
                          // intentional progress instead of a flicker.
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              _loadingStatus,
                              key: ValueKey(_loadingStatus),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white60,
                                letterSpacing: 1.2,
                              ),
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

