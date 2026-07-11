import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' show Platform;
import '../providers/app_state.dart';
import '../providers/download_provider.dart';
import '../models/download_item.dart';
import '../services/haptic_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/stat_card.dart';
import '../widgets/glass_list_tile.dart';
import 'security_setup_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final dlProvider = context.watch<DownloadProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;

    final completed =
        dlProvider.queue.where((d) => d.status == DownloadStatus.done).length;
    final active =
        dlProvider.queue.where((d) => d.status == DownloadStatus.downloading || d.status == DownloadStatus.queued).length;
    final totalStorage = dlProvider.totalStorage * 1048576;
    final freeStorage = dlProvider.freeStorage * 1048576;
    final usedBytes = totalStorage - freeStorage;
    final usagePercent = totalStorage > 0 ? usedBytes / totalStorage : 0.0;

    String formatBytes(double bytes) {
      if (bytes < 1024) return '${bytes.toInt()} B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: appState.trueAmoledDark && isDark
                  ? Colors.black
                  : cs.surface,
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: topPadding + 24),
              ),
              SliverToBoxAdapter(child: _buildHeader(context, appState, dlProvider, formatBytes)),
              SliverToBoxAdapter(child: _buildStatsRow(context, completed, active)),
              SliverToBoxAdapter(child: _buildStorageCard(context, formatBytes, usedBytes, freeStorage, usagePercent)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  CupertinoIcons.paintbrush,
                  'Appearance',
                  _buildAppearanceItems(context, appState, isDark, cs),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  CupertinoIcons.arrow_down_circle,
                  'Downloads',
                  _buildDownloadItems(context, appState),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  CupertinoIcons.arrow_clockwise_circle,
                  'Smart Retry',
                  _buildRetryItems(context, appState),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  CupertinoIcons.clock,
                  'Download Scheduler',
                  _buildSchedulerItems(context, appState),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  CupertinoIcons.lock_shield,
                  'Security',
                  _buildSecurityItems(context, appState),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  CupertinoIcons.hand_draw,
                  'Haptics',
                  _buildHapticItems(context, appState),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  CupertinoIcons.info_circle,
                  'About',
                  _buildAboutItems(context, appState),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppState appState, DownloadProvider dlProvider, String Function(double) formatBytes) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: cs.primary.withValues(alpha: isDark ? 0.15 : 0.1),
            ),
            alignment: Alignment.center,
            child: Icon(
              CupertinoIcons.compass_fill,
              size: 32,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DirXplore Pro',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Version ${appState.appVersion}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, int completed, int active) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          StatCard(
            icon: CupertinoIcons.check_mark_circled_solid,
            label: 'Completed',
            value: completed.toString(),
            iconColor: CupertinoColors.activeGreen,
          ),
          const SizedBox(width: 10),
          StatCard(
            icon: CupertinoIcons.arrow_down_circle_fill,
            label: 'Active',
            value: active.toString(),
            iconColor: CupertinoColors.activeBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildStorageCard(BuildContext context, String Function(double) formatBytes, double usedBytes, double freeBytes, double usagePercent) {
    final cs = Theme.of(context).colorScheme;

    if (usedBytes <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: GlassCard(
        borderRadius: 18,
        blurSigma: 20,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.archivebox, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Storage',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Used',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Container(
                      height: 6,
                      color: cs.onSurface.withValues(alpha: 0.06),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: usagePercent.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Free',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  formatBytes(usedBytes),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  formatBytes(freeBytes),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, IconData icon, String title, List<Widget> tiles) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                Icon(icon, size: 15, color: cs.primary.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          GlassCard(
            borderRadius: 22,
            blurSigma: 25,
            child: Column(
              children: _insertDividers(tiles, context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _insertDividers(List<Widget> tiles, BuildContext context) {
    if (tiles.isEmpty) return tiles;
    final result = <Widget>[tiles.first];
    for (int i = 1; i < tiles.length; i++) {
      result.add(const GlassTileDivider());
      result.add(tiles[i]);
    }
    return result;
  }

  List<Widget> _buildAppearanceItems(BuildContext context, AppState appState, bool isDark, ColorScheme cs) {
    return [
      GlassDropdownTile<ThemeMode>(
        icon: isDark ? CupertinoIcons.moon : CupertinoIcons.sun_max,
        title: 'Theme',
        value: appState.themeMode,
        items: const [
          DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
          DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
        ],
        onChanged: (val) {
          if (val != null) appState.setThemeMode(val);
        },
      ),
      GlassSwitchTile(
        icon: CupertinoIcons.circle_lefthalf_fill,
        iconBackground: cs.onSurface.withValues(alpha: 0.08),
        title: 'True AMOLED Black',
        subtitle: 'Pure black background for OLED screens',
        value: appState.trueAmoledDark,
        onChanged: (val) => appState.setTrueAmoledDark(val),
      ),
    ];
  }

  List<Widget> _buildDownloadItems(BuildContext context, AppState appState) {
    return [
      GlassListTile(
        icon: CupertinoIcons.folder,
        title: 'Default Save Directory',
        subtitle: _truncatePath(appState.defaultSavePath, 40),
        showChevron: true,
        onTap: () => _pickDirectory(context, appState),
      ),
      GlassDropdownTile<int>(
        icon: CupertinoIcons.tray_full,
        title: 'Max Concurrent Downloads',
        subtitle: '${appState.maxConcurrentDownloads} files at once',
        value: appState.maxConcurrentDownloads,
        items: [1, 2, 3, 4, 5, 10]
            .map((e) => DropdownMenuItem(value: e, child: Text(e.toString())))
            .toList(),
        onChanged: (val) {
          if (val != null) appState.setMaxConcurrentDownloads(val);
        },
      ),
      GlassSwitchTile(
        icon: CupertinoIcons.bell,
        title: 'Show Download Notifications',
        subtitle: 'Display progress in notification panel',
        value: appState.showDownloadNotifications,
        onChanged: (val) => appState.setShowDownloadNotifications(val),
      ),
      GlassSliderTile(
        title: 'Speed Limiter (Per Download)',
        value: appState.speedLimitCap.toDouble(),
        min: 0,
        max: 10000,
        divisions: 20,
        label: appState.speedLimitCap == 0
            ? 'Unlimited'
            : '${appState.speedLimitCap} KB/s',
        onChanged: (val) => appState.setSpeedLimitCap(val.toInt()),
      ),
      GlassSwitchTile(
        icon: CupertinoIcons.square_on_square,
        title: 'Smart Folder Routing',
        subtitle: 'Auto-sort by extension',
        value: appState.smartFolderRouting,
        onChanged: (val) => appState.setSmartFolderRouting(val),
      ),
      GlassSwitchTile(
        icon: CupertinoIcons.wifi,
        title: 'Download on Wi-Fi Only',
        value: appState.downloadOnWifiOnly,
        onChanged: (val) => appState.setDownloadOnWifiOnly(val),
      ),
      GlassSwitchTile(
        icon: CupertinoIcons.battery_25,
        title: 'Pause If Battery < 15%',
        subtitle: 'Preserve battery life',
        value: appState.pauseLowBattery,
        onChanged: (val) => appState.setPauseLowBattery(val),
      ),
      GlassSwitchTile(
        icon: CupertinoIcons.eye,
        title: 'Keep Screen Awake',
        subtitle: 'Prevent sleep while downloading',
        value: appState.keepScreenAwake,
        onChanged: (val) => appState.setKeepScreenAwake(val),
      ),
      if (appState.keepScreenAwake)
        GlassSliderTile(
          title: 'Auto-off Timer',
          subtitle: 'Turn off screen wake after set time',
          value: appState.keepScreenAwakeTimerMinutes.toDouble(),
          min: 0,
          max: 60,
          divisions: 12,
          label: appState.keepScreenAwakeTimerMinutes == 0
              ? 'Off'
              : '${appState.keepScreenAwakeTimerMinutes} min',
          onChanged: (val) =>
              appState.setKeepScreenAwakeTimerMinutes(val.round()),
        ),
      GlassSwitchTile(
        icon: CupertinoIcons.tray_arrow_down,
        title: 'Auto-Categorize Downloads',
        subtitle: 'Sort completed downloads by file type',
        value: appState.autoCategorizeEnabled,
        onChanged: (val) => appState.setAutoCategorizeEnabled(val),
      ),
    ];
  }

  List<Widget> _buildRetryItems(BuildContext context, AppState appState) {
    return [
      GlassDropdownTile<int>(
        icon: CupertinoIcons.arrow_clockwise,
        title: 'Max Retry Count',
        subtitle: '${appState.retryCount} retries',
        value: appState.retryCount,
        items: [1, 2, 3, 5, 10]
            .map((e) => DropdownMenuItem(value: e, child: Text(e.toString())))
            .toList(),
        onChanged: (val) {
          if (val != null) appState.setRetryCount(val);
        },
      ),
      GlassDropdownTile<int>(
        icon: CupertinoIcons.timer,
        title: 'Retry Delay',
        subtitle: '${appState.retryDelaySeconds} seconds',
        value: appState.retryDelaySeconds,
        items: [5, 10, 15, 30, 60, 120]
            .map((e) => DropdownMenuItem(value: e, child: Text('${e}s')))
            .toList(),
        onChanged: (val) {
          if (val != null) appState.setRetryDelaySeconds(val);
        },
      ),
      GlassSwitchTile(
        icon: CupertinoIcons.refresh_thick,
        title: 'Auto Retry',
        subtitle: 'Automatically retry failed downloads',
        value: appState.autoRetry,
        onChanged: (val) => appState.setAutoRetry(val),
      ),
    ];
  }

  List<Widget> _buildSchedulerItems(BuildContext context, AppState appState) {
    final tiles = <Widget>[
      GlassSwitchTile(
        icon: CupertinoIcons.slider_horizontal_3,
        title: 'Enable Scheduler',
        subtitle: 'Respect scheduling preferences for downloads',
        value: appState.enableScheduler,
        onChanged: (val) => appState.setEnableScheduler(val),
      ),
    ];

    if (appState.enableScheduler) {
      tiles.add(GlassSwitchTile(
        icon: CupertinoIcons.wifi,
        title: 'Wi-Fi Only Scheduling',
        subtitle: 'Only download queued items on Wi-Fi',
        value: appState.schedulerWifiOnly,
        onChanged: (val) => appState.setSchedulerWifiOnly(val),
      ));
      tiles.add(GlassSwitchTile(
        icon: CupertinoIcons.battery_100,
        title: 'Charging Only',
        subtitle: 'Only download while device is charging',
        value: appState.schedulerChargingOnly,
        onChanged: (val) => appState.setSchedulerChargingOnly(val),
      ));
    }

    return tiles;
  }

  List<Widget> _buildSecurityItems(BuildContext context, AppState appState) {
    final tiles = <Widget>[
      GlassDropdownTile<String>(
        icon: CupertinoIcons.lock_shield,
        title: 'App Lock Type',
        subtitle: appState.lockType == 'none'
            ? 'Disabled'
            : appState.lockType == 'device'
                ? 'Device (Fingerprint/PIN)'
                : 'Custom App PIN',
        value: appState.lockType,
        items: const [
          DropdownMenuItem(value: 'none', child: Text('None')),
          DropdownMenuItem(value: 'device', child: Text('Device')),
          DropdownMenuItem(value: 'custom', child: Text('Custom PIN')),
        ],
        onChanged: (val) {
          if (val == 'custom' && appState.customPinHash.isEmpty) {
            _showSecuritySetup(context);
          } else {
            if (val != null) appState.setLockType(val);
          }
        },
      ),
      GlassDropdownTile<int>(
        icon: CupertinoIcons.timer,
        title: 'Inactivity Auto-Lock',
        subtitle: appState.autoLockSeconds == 0
            ? 'Immediate'
            : appState.autoLockSeconds == 30
                ? '30 Seconds'
                : '${appState.autoLockSeconds ~/ 60} Minute(s)',
        value: appState.autoLockSeconds,
        items: const [
          DropdownMenuItem(value: 0, child: Text('Immediate')),
          DropdownMenuItem(value: 30, child: Text('30s')),
          DropdownMenuItem(value: 60, child: Text('1m')),
          DropdownMenuItem(value: 120, child: Text('2m')),
        ],
        onChanged: (val) {
          if (val != null) appState.setAutoLockSeconds(val);
        },
      ),
    ];

    if (appState.lockType == 'custom') {
      tiles.add(GlassListTile(
        icon: CupertinoIcons.pencil,
        title: 'Configure Custom PIN',
        subtitle: 'Change PIN or security question',
        showChevron: true,
        onTap: () => _showSecuritySetup(context),
      ));
    }

    return tiles;
  }

  List<Widget> _buildHapticItems(BuildContext context, AppState appState) {
    return [
      GlassSwitchTile(
        icon: CupertinoIcons.hand_draw,
        title: 'Haptic Feedback',
        subtitle: 'Vibration on taps and actions',
        value: appState.hapticFeedbackEnabled,
        onChanged: (val) => appState.setHapticFeedbackEnabled(val),
      ),
    ];
  }

  List<Widget> _buildAboutItems(BuildContext context, AppState appState) {
    return [
      GlassListTile(
        icon: CupertinoIcons.info_circle,
        title: 'Version',
        subtitle: appState.appVersion,
      ),
      const GlassListTile(
        icon: CupertinoIcons.heart,
        title: 'Created by RAKIB',
        showChevron: false,
      ),
    ];
  }

  String _truncatePath(String path, int max) {
    if (path.length <= max) return path;
    return '...${path.substring(path.length - max + 3)}';
  }

  void _pickDirectory(BuildContext context, AppState appState) async {
    if (Platform.isIOS) {
      final picked = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Persistent Download Folder'),
          content: const Text(
            'Choose a folder outside the app sandbox so downloads survive app deletion.',
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            CupertinoDialogAction(
              child: const Text('Choose Folder'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );
      if (picked != true) return;
      final path = await appState.pickDownloadFolder();
      if (path != null && context.mounted) {
        _showSnackBar(context, 'Downloads will now save to a persistent folder.');
      }
    } else {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        appState.setDefaultSavePath(selectedDirectory);
      }
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF1C1C1E)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showSecuritySetup(BuildContext context) {
    HapticService.light();
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (context) => const SecuritySetupScreen()),
    );
  }
}
