/*
 * Moonode Launcher
 * Copyright (C) 2025 Moonode
 *
 * Settings screen - Access installed apps and system settings
 */

import 'dart:typed_data';
import 'package:flutter/material.dart';
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
  List<Map<String, dynamic>> _apps = [];
  bool _isLoading = true;
  bool _isDefaultLauncher = false;

  @override
  void initState() {
    super.initState();
    _loadApps();
    _checkDefaultLauncher();
  }

  Future<void> _loadApps() async {
    try {
      final apps = await widget.launcherChannel.getApplications();
      setState(() {
        _apps = apps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkDefaultLauncher() async {
    final isDefault = await widget.launcherChannel.isDefaultLauncher();
    setState(() {
      _isDefaultLauncher = isDefault;
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
      body: Row(
        children: [
          // Left panel - Quick actions
          Container(
            width: 300,
            color: const Color(0xFF1A1F2E),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Default launcher status
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isDefaultLauncher 
                        ? const Color(0xFF22C55E).withOpacity(0.2)
                        : const Color(0xFFFF6B6B).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isDefaultLauncher ? Icons.check_circle : Icons.warning,
                        color: _isDefaultLauncher 
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFFF6B6B),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isDefaultLauncher 
                              ? 'Default Launcher ✓'
                              : 'Not Default Launcher',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Android Settings
                _buildActionButton(
                  icon: Icons.settings,
                  label: 'Android Settings',
                  onPressed: () => widget.launcherChannel.openSettings(),
                ),
                const SizedBox(height: 8),

                // Launch Moonode App
                _buildActionButton(
                  icon: Icons.tv,
                  label: 'Open Moonode App',
                  color: const Color(0xFFF5D742),
                  onPressed: () => widget.launcherChannel.launchMoonodeApp(),
                ),

                const Spacer(),

                // Version info
                const Text(
                  'Moonode Launcher v1.0.0',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '© 2025 Moonode',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Right panel - Apps list
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Installed Apps',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFF5D742),
                              ),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 6,
                              childAspectRatio: 0.8,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: _apps.length,
                            itemBuilder: (context, index) {
                              final app = _apps[index];
                              return _buildAppCard(app);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppCard(Map<String, dynamic> app) {
    final name = app['name'] as String? ?? 'Unknown';
    final packageName = app['packageName'] as String? ?? '';
    final iconBytes = app['icon'] as Uint8List?;
    final bannerBytes = app['banner'] as Uint8List?;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.launcherChannel.launchApp(packageName),
        onLongPress: () => _showAppOptions(app),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F2E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF2A2F3E),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: bannerBytes != null
                      ? Image.memory(bannerBytes, fit: BoxFit.cover)
                      : iconBytes != null
                          ? Image.memory(iconBytes, fit: BoxFit.cover)
                          : const Icon(
                              Icons.apps,
                              size: 32,
                              color: Colors.white54,
                            ),
                ),
              ),
              const SizedBox(height: 8),
              // App name
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAppOptions(Map<String, dynamic> app) {
    final name = app['name'] as String? ?? 'Unknown';
    final packageName = app['packageName'] as String? ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        title: Text(
          name,
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info, color: Color(0xFF4FB3FF)),
              title: const Text('App Info', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                widget.launcherChannel.openAppInfo(packageName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Color(0xFFFF6B6B)),
              title: const Text('Uninstall', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                widget.launcherChannel.uninstallApp(packageName);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}

