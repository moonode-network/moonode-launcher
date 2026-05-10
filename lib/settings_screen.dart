/*
 * Moonode Launcher
 * Copyright (C) 2026 Moonode
 *
 * Settings screen - Quick actions and system settings access.
 *
 * Fire TV adds a "HOME Guardian" accessibility-service toggle so the user can
 * reclaim the HOME button on devices where Amazon protects its launcher.
 * Android TV never sees that tile because the standard launcher picker works.
 */

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'launcher_channel.dart';

class SettingsScreen extends StatefulWidget {
  final LauncherChannel launcherChannel;
  final SharedPreferences sharedPreferences;

  const SettingsScreen({
    super.key,
    required this.launcherChannel,
    required this.sharedPreferences,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool _isDefaultLauncher = false;
  bool _isFireTv = false;
  bool _isHomeHijackEnabled = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
    _loadAppVersion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user comes back from system Accessibility settings, re-check
    // whether HOME Guardian is now enabled.
    if (state == AppLifecycleState.resumed) {
      _refreshAll();
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _checkDefaultLauncher(),
      _loadDeviceInfo(),
      _checkHomeHijack(),
    ]);
  }

  Future<void> _checkDefaultLauncher() async {
    final isDefault = await widget.launcherChannel.isDefaultLauncher();
    if (!mounted) return;
    setState(() {
      _isDefaultLauncher = isDefault;
    });
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final info = await widget.launcherChannel.getDeviceInfo();
      if (!mounted) return;
      setState(() {
        _isFireTv = info['isFireTv'] == true;
      });
    } catch (_) {
      // Older builds without getDeviceInfo - safe default.
    }
  }

  Future<void> _checkHomeHijack() async {
    try {
      final enabled = await widget.launcherChannel.isHomeHijackEnabled();
      if (!mounted) return;
      setState(() {
        _isHomeHijackEnabled = enabled;
      });
    } catch (_) {
      // Older builds without isHomeHijackEnabled - safe default.
    }
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = 'v${packageInfo.version}+${packageInfo.buildNumber}';
    });
  }

  Future<void> _confirmAndChooseLauncher() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        title: const Text(
          'Choose Default Launcher',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          _isFireTv
              ? 'Fire TV does not let you swap the HOME launcher from a picker. '
                  'We will open this app\u2019s info page so you can press '
                  '\u201cClear defaults\u201d or \u201cUninstall\u201d to return '
                  'to the Amazon launcher.'
              : 'This will open the system HOME launcher picker so you can '
                  'switch back to your previous launcher (or re-select Moonode).',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.launcherChannel.chooseDefaultLauncher();
    }
  }

  void _showHijackPauseToast({required String reason}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A1F2E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Text(
          'HOME Guardian paused for 5 min ($reason). Returning to Moonode '
          're-arms it instantly.',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _showHomeHijackInstructions() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        title: const Text(
          'Enable HOME Guardian',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Fire TV blocks third-party launchers from replacing HOME. '
          'To make HOME always return to Moonode, we use an accessibility '
          'service that detects when the Amazon home screen appears and '
          'immediately switches back to Moonode.\n\n'
          'On the next screen:\n'
          '  1. Scroll to "Services"\n'
          '  2. Open "Moonode HOME Guardian"\n'
          '  3. Toggle it ON and confirm\n\n'
          'Moonode does NOT read screen content; the service only watches '
          'which app is in the foreground.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open Accessibility Settings'),
          ),
        ],
      ),
    );
    if (proceed == true) {
      await widget.launcherChannel.openAccessibilitySettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1F2E),
        title: const Row(
          children: [
            Icon(Icons.brightness_2, color: Color(0xFFF5D742)),
            SizedBox(width: 12),
            Text(
              'Moonode Launcher Settings',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _isDefaultLauncher
                        ? const Color(0xFF22C55E).withOpacity(0.2)
                        : const Color(0xFFFF6B6B).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isDefaultLauncher ? Icons.check_circle : Icons.warning,
                        color: _isDefaultLauncher
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFFF6B6B),
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _isDefaultLauncher
                              ? 'Default Launcher'
                              : _isFireTv
                                  ? 'Fire TV \u2014 use HOME Guardian below to reclaim HOME'
                                  : 'Not Default Launcher',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                if (_isFireTv) ...[
                  _buildHomeHijackTile(),
                  const SizedBox(height: 12),
                ],

                _buildActionButton(
                  icon: Icons.wifi,
                  label: 'Wi-Fi Settings',
                  color: const Color(0xFF4FB3FF),
                  onPressed: () async {
                    if (_isFireTv && _isHomeHijackEnabled) {
                      _showHijackPauseToast(reason: 'Wi-Fi Settings');
                    }
                    await widget.launcherChannel.openWifiSettings();
                  },
                ),
                const SizedBox(height: 12),

                _buildActionButton(
                  icon: Icons.settings,
                  label: 'Android Settings',
                  onPressed: () async {
                    if (_isFireTv && _isHomeHijackEnabled) {
                      _showHijackPauseToast(reason: 'Android Settings');
                    }
                    await widget.launcherChannel.openSettings();
                  },
                ),
                const SizedBox(height: 12),

                _buildActionButton(
                  icon: Icons.tv,
                  label: 'Open Moonode App',
                  color: const Color(0xFFF5D742),
                  onPressed: () => widget.launcherChannel.launchMoonodeApp(),
                ),
                const SizedBox(height: 12),

                if (_isFireTv && _isHomeHijackEnabled) ...[
                  _buildActionButton(
                    icon: Icons.pause_circle_outline,
                    label: 'Pause HOME Guardian (5 min)',
                    color: const Color(0xFFF5D742),
                    onPressed: () async {
                      await widget.launcherChannel.pauseHomeHijack();
                      if (!mounted) return;
                      _showHijackPauseToast(reason: 'manual pause');
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                _buildActionButton(
                  icon: Icons.swap_horiz,
                  label: _isFireTv
                      ? 'Disable / Uninstall Moonode Launcher'
                      : 'Choose Default Launcher',
                  color: const Color(0xFFFF6B6B),
                  onPressed: _confirmAndChooseLauncher,
                ),

                const SizedBox(height: 32),

                Center(
                  child: Column(
                    children: [
                      Text(
                        'Moonode Launcher $_appVersion',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '\u00a9 2026 Moonode',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeHijackTile() {
    final on = _isHomeHijackEnabled;
    final color = on ? const Color(0xFF22C55E) : const Color(0xFFF5D742);
    final label = on
        ? 'HOME Guardian: ON \u2014 HOME returns to Moonode'
        : 'Enable HOME Guardian (Fire TV)';
    final subtitle = on
        ? 'Pressing HOME on the remote will snap back to Moonode automatically.'
        : 'Required on Fire TV. Opens Accessibility settings so you can switch '
            'on \u201cMoonode HOME Guardian\u201d.';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: on ? widget.launcherChannel.openAccessibilitySettings : _showHomeHijackInstructions,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.6)),
            borderRadius: BorderRadius.circular(12),
            color: on ? color.withOpacity(0.08) : Colors.transparent,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                on ? Icons.shield : Icons.shield_outlined,
                color: color,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (on)
                const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color color = const Color(0xFF4FB3FF),
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: color, fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
