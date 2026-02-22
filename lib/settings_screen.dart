/*
 * Moonode Launcher
 * Copyright (C) 2026 Moonode
 *
 * Settings screen - Quick actions and system settings access
 */

import 'package:flutter/material.dart';
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

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDefaultLauncher = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _checkDefaultLauncher();
    _loadAppVersion();
  }

  Future<void> _checkDefaultLauncher() async {
    final isDefault = await widget.launcherChannel.isDefaultLauncher();
    setState(() {
      _isDefaultLauncher = isDefault;
    });
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = 'v${packageInfo.version}+${packageInfo.buildNumber}';
    });
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
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Default launcher status
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
                      Text(
                        _isDefaultLauncher
                            ? 'Default Launcher'
                            : 'Not Default Launcher',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                _buildActionButton(
                  icon: Icons.settings,
                  label: 'Android Settings',
                  onPressed: () => widget.launcherChannel.openSettings(),
                ),
                const SizedBox(height: 12),

                _buildActionButton(
                  icon: Icons.tv,
                  label: 'Open Moonode App',
                  color: const Color(0xFFF5D742),
                  onPressed: () => widget.launcherChannel.launchMoonodeApp(),
                ),

                const Spacer(),

                // Version & copyright
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
              Text(
                label,
                style: TextStyle(color: color, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
