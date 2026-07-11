import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:yaml/yaml.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import '../providers/proxy_provider.dart';
import '../providers/app_state.dart';
import '../models/proxy_model.dart';
import '../services/haptic_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/stat_card.dart';
import '../widgets/glass_list_tile.dart';
import '../widgets/section_title.dart';

class ProxyTab extends StatefulWidget {
  const ProxyTab({super.key});

  @override
  State<ProxyTab> createState() => _ProxyTabState();
}

class _ProxyTabState extends State<ProxyTab> {
  bool _dnsThroughProxy = false;
  bool _proxyAllTraffic = true;
  bool _bypassLocal = true;
  bool _autoReconnect = false;

  int _uptimeSeconds = 0;
  Timer? _uptimeTimer;
  final int _totalDataTransferred = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncUptimeTimer());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncUptimeTimer();
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    super.dispose();
  }

  void _syncUptimeTimer() {
    final provider = context.read<AppProxyProvider>();
    if (provider.activeProxy != null) {
      _uptimeTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _uptimeSeconds++);
      });
    } else {
      _uptimeTimer?.cancel();
      _uptimeTimer = null;
      _uptimeSeconds = 0;
    }
  }

  String get _uptimeFormatted {
    final h = _uptimeSeconds ~/ 3600;
    final m = (_uptimeSeconds % 3600) ~/ 60;
    final s = _uptimeSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Color _protocolColor(ProxyProtocol p, bool isDark) {
    switch (p) {
      case ProxyProtocol.SOCKS5:
        return const Color(0xFF34C759);
      case ProxyProtocol.SOCKS4:
        return const Color(0xFF007AFF);
      case ProxyProtocol.HTTP:
        return const Color(0xFFFF9500);
      case ProxyProtocol.HTTPS:
        return const Color(0xFFAF52DE);
    }
  }

  String _protocolLabel(ProxyProtocol p) {
    switch (p) {
      case ProxyProtocol.SOCKS5:
        return 'SOCKS5';
      case ProxyProtocol.SOCKS4:
        return 'SOCKS4';
      case ProxyProtocol.HTTP:
        return 'HTTP';
      case ProxyProtocol.HTTPS:
        return 'HTTPS';
    }
  }

  String _latencyLabel(int? ms) {
    if (ms == null) return 'Not tested';
    if (ms == -1) return 'Failed';
    return '${ms}ms';
  }

  Color _latencyColor(int? ms, bool isDark) {
    if (ms == null) return isDark ? Colors.grey[400]! : Colors.grey[500]!;
    if (ms == -1) return const Color(0xFFFF3B30);
    if (ms < 200) return const Color(0xFF34C759);
    if (ms < 500) return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
  }

  @override
  Widget build(BuildContext context) {
    final proxyProvider = context.watch<AppProxyProvider>();
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;
    final proxies = proxyProvider.proxies;
    final active = proxyProvider.activeProxy;
    final isConnected = active != null;

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
              SliverToBoxAdapter(
                child: _buildHeader(context, isDark, cs),
              ),
              SliverToBoxAdapter(
                child: _buildConnectionStatus(context, proxyProvider, isDark, cs, isConnected, active),
              ),
              SliverToBoxAdapter(
                child: _buildQuickToggle(context, proxyProvider, isDark, cs, isConnected, proxies),
              ),
              if (isConnected)
                SliverToBoxAdapter(
                  child: _buildActiveProxyCard(context, proxyProvider, active, isDark, cs),
                ),
              if (proxies.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: const SectionTitle(title: 'Saved Proxies'),
                ),
                SliverToBoxAdapter(
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: List.generate(proxies.length, (i) {
                        final proxy = proxies[i];
                        return _buildProxyRow(context, proxyProvider, proxy, isDark, cs);
                      }),
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: _buildAddButton(context, isDark, cs),
                ),
              ),
              SliverToBoxAdapter(
                child: const SectionTitle(title: 'Statistics'),
              ),
              SliverToBoxAdapter(
                child: _buildStatsRow(context, proxyProvider, isDark, cs, active),
              ),
              SliverToBoxAdapter(
                child: const SizedBox(height: 20),
              ),
              SliverToBoxAdapter(
                child: const SectionTitle(title: 'Advanced'),
              ),
              SliverToBoxAdapter(
                child: _buildAdvancedSection(context, proxyProvider, isDark, cs),
              ),
              SliverToBoxAdapter(
                child: const SizedBox(height: 100),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
      child: Text(
        'Proxy',
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
          letterSpacing: 0.37,
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(
    BuildContext context,
    AppProxyProvider provider,
    bool isDark,
    ColorScheme cs,
    bool isConnected,
    ProxyModel? active,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _AnimatedStatusDot(isConnected: isConnected),
                const SizedBox(width: 10),
                Text(
                  isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                if (isConnected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _protocolColor(active!.protocol, isDark).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _protocolLabel(active.protocol),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _protocolColor(active.protocol, isDark),
                      ),
                    ),
                  ),
              ],
            ),
            if (isConnected && active != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(CupertinoIcons.globe, size: 13, color: cs.onSurface.withValues(alpha: 0.4)),
                  const SizedBox(width: 6),
                  Text(
                    '${active.host}:${active.port}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const Spacer(),
                  Icon(CupertinoIcons.clock, size: 13, color: cs.onSurface.withValues(alpha: 0.4)),
                  const SizedBox(width: 6),
                  Text(
                    _uptimeFormatted,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
            if (!isConnected) ...[
              const SizedBox(height: 10),
              Text(
                'All traffic is routed directly',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickToggle(
    BuildContext context,
    AppProxyProvider provider,
    bool isDark,
    ColorScheme cs,
    bool isConnected,
    List<ProxyModel> proxies,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(4),
        child: GlassSwitchTile(
          title: 'Enable Proxy',
          subtitle: 'Route all supported requests through the selected proxy',
          value: isConnected,
          onChanged: (val) {
            HapticService.light();
            if (val && proxies.isNotEmpty) {
              provider.toggleProxy(proxies[0].id, true);
            } else if (!val && provider.activeProxy != null) {
              provider.toggleProxy(provider.activeProxy!.id, false);
            }
          },
        ),
      ),
    );
  }

  Widget _buildActiveProxyCard(
    BuildContext context,
    AppProxyProvider provider,
    ProxyModel active,
    bool isDark,
    ColorScheme cs,
  ) {
    final protocolColor = _protocolColor(active.protocol, isDark);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.globe, size: 16, color: protocolColor),
                const SizedBox(width: 8),
                Text(
                  'Active Proxy',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: protocolColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: protocolColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _protocolLabel(active.protocol),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: protocolColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildProxyDetailRow('Host', active.host, cs),
            _buildProxyDetailRow('Port', active.port.toString(), cs),
            _buildProxyDetailRow(
              'Authentication',
              (active.username != null && active.username!.isNotEmpty) ? 'Enabled' : 'Disabled',
              cs,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Latency',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                Text(
                  _latencyLabel(active.latencyMs),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _latencyColor(active.latencyMs, isDark),
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 32,

                  onPressed: () {
                    HapticService.light();
                    provider.testProxyLatency(active);
                  },
                  child: Icon(CupertinoIcons.waveform_path_ecg, size: 18, color: cs.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProxyDetailRow(String label, String value, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProxyRow(
    BuildContext context,
    AppProxyProvider provider,
    ProxyModel proxy,
    bool isDark,
    ColorScheme cs,
  ) {
    final isThisActive = proxy.isActive;
    final protocolColor = _protocolColor(proxy.protocol, isDark);

    return Dismissible(
      key: ValueKey(proxy.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Icon(CupertinoIcons.delete, color: const Color(0xFFFF3B30)),
      ),
      secondaryBackground: Container(),
      confirmDismiss: (direction) async {
        HapticService.light();
        if (direction == DismissDirection.startToEnd) {
          provider.deleteProxy(proxy.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Deleted ${proxy.displayUri}'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
        return false;
      },
      child: GestureDetector(
        onTap: () {
          HapticService.selection();
          if (!isThisActive) {
            provider.toggleProxy(proxy.id, true);
          }
        },
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: protocolColor.withValues(alpha: isDark ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  CupertinoIcons.globe,
                  size: 15,
                  color: protocolColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          proxy.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          ':${proxy.port}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: protocolColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _protocolLabel(proxy.protocol),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: protocolColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (proxy.latencyMs != null && proxy.latencyMs! >= 0)
                          Text(
                            '${proxy.latencyMs}ms',
                            style: TextStyle(
                              fontSize: 12,
                              color: _latencyColor(proxy.latencyMs, isDark),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isThisActive)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759),
                    shape: BoxShape.circle,
                  ),
                )
              else
                const SizedBox(width: 8),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showProxyActions(context, provider, proxy),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: Icon(
                    CupertinoIcons.ellipsis,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProxyActions(BuildContext context, AppProxyProvider provider, ProxyModel proxy) {
    final cs = Theme.of(context).colorScheme;
    HapticService.selection();

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1C1C1E)
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              borderRadius: BorderRadius.zero,
              child: Row(
                children: [
                  Icon(CupertinoIcons.waveform_path_ecg, size: 20, color: cs.primary),
                  const SizedBox(width: 12),
                  Text('Test Ping', style: TextStyle(fontSize: 16, color: cs.onSurface)),
                ],
              ),
              onPressed: () {
                Navigator.pop(ctx);
                HapticService.light();
                provider.testProxyLatency(proxy);
              },
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              borderRadius: BorderRadius.zero,
              child: Row(
                children: [
                  Icon(CupertinoIcons.pencil, size: 20, color: cs.primary),
                  const SizedBox(width: 12),
                  Text('Edit', style: TextStyle(fontSize: 16, color: cs.onSurface)),
                ],
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _showEditProxyDialog(context, proxy);
              },
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              borderRadius: BorderRadius.zero,
              child: Row(
                children: [
                  Icon(CupertinoIcons.delete, size: 20, color: const Color(0xFFFF3B30)),
                  const SizedBox(width: 12),
                  Text('Delete', style: TextStyle(fontSize: 16, color: const Color(0xFFFF3B30))),
                ],
              ),
              onPressed: () {
                Navigator.pop(ctx);
                HapticService.light();
                provider.deleteProxy(proxy.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, bool isDark, ColorScheme cs) {
    return GestureDetector(
      onTap: () => _showAddProxyDialog(context),
      onLongPress: () => _showBulkImportDialog(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.primary.withValues(alpha: isDark ? 0.2 : 0.15),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.add, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Add New Proxy',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(
    BuildContext context,
    AppProxyProvider provider,
    bool isDark,
    ColorScheme cs,
    ProxyModel? active,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          StatCard(
            label: 'Current connection',
            value: active?.latencyMs != null && active!.latencyMs! >= 0
                ? '${active.latencyMs}ms'
                : '---',
            icon: CupertinoIcons.waveform_path_ecg,
            iconColor: _latencyColor(active?.latencyMs, isDark),
          ),
          const SizedBox(width: 8),
          StatCard(
            label: 'Transferred',
            value: '${_totalDataTransferred} GB',
            icon: CupertinoIcons.arrow_up_arrow_down,
          ),
          const SizedBox(width: 8),
          StatCard(
            label: 'Session',
            value: active != null ? _uptimeFormatted : '---',
            icon: CupertinoIcons.clock,
          ),
          const SizedBox(width: 8),
          StatCard(
            label: 'Saved',
            value: '${provider.proxies.length}',
            icon: CupertinoIcons.tray_full,
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSection(
    BuildContext context,
    AppProxyProvider provider,
    bool isDark,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            GlassSwitchTile(
              icon: CupertinoIcons.arrow_right_arrow_left,
              title: 'DNS through proxy',
              value: _dnsThroughProxy,
              onChanged: (val) => setState(() => _dnsThroughProxy = val),
            ),
            const GlassTileDivider(),
            GlassSwitchTile(
              icon: CupertinoIcons.globe,
              title: 'Proxy all traffic',
              value: _proxyAllTraffic,
              onChanged: (val) => setState(() => _proxyAllTraffic = val),
            ),
            const GlassTileDivider(),
            GlassSwitchTile(
              icon: CupertinoIcons.house,
              title: 'Bypass local addresses',
              value: _bypassLocal,
              onChanged: (val) => setState(() => _bypassLocal = val),
            ),
            const GlassTileDivider(),
            GlassSwitchTile(
              icon: CupertinoIcons.arrow_clockwise,
              title: 'Auto reconnect',
              value: _autoReconnect,
              onChanged: (val) => setState(() => _autoReconnect = val),
            ),
            const GlassTileDivider(),
            GlassListTile(
              icon: CupertinoIcons.waveform_path_ecg,
              title: 'Test Connection',
              subtitle: 'Ping all saved proxies',
              showChevron: true,
              onTap: () {
                HapticService.light();
                provider.testAllProxies();
              },
            ),
            const GlassTileDivider(),
            GlassListTile(
              icon: CupertinoIcons.square_arrow_down,
              title: 'Import Configuration',
              subtitle: 'YAML / URI list',
              showChevron: true,
              onTap: () {
                HapticService.selection();
                _showImportOptions(context);
              },
            ),
            const GlassTileDivider(),
            GlassListTile(
              icon: CupertinoIcons.square_arrow_up,
              title: 'Export Configuration',
              subtitle: '${provider.proxies.length} proxies',
              showChevron: true,
              onTap: () {
                HapticService.selection();
                _exportConfiguration(context, provider);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showImportOptions(BuildContext context) {
    HapticService.selection();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1C1C1E)
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              borderRadius: BorderRadius.zero,
              child: Row(
                children: [
                  Icon(CupertinoIcons.doc_text, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Text('Import YAML File', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                ],
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _importYamlProxies(context);
              },
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              borderRadius: BorderRadius.zero,
              child: Row(
                children: [
                  Icon(CupertinoIcons.pencil, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Text('Bulk Import URIs', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                ],
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _showBulkImportDialog(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAddProxyDialog(BuildContext context) {
    HapticService.light();
    final hostCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '1080');
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Add Proxy'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: hostCtrl,
              placeholder: 'Host IP / Domain',
              clearButtonMode: OverlayVisibilityMode.editing,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: portCtrl,
              placeholder: 'Port',
              keyboardType: TextInputType.number,
              clearButtonMode: OverlayVisibilityMode.editing,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: userCtrl,
              placeholder: 'Username (Optional)',
              clearButtonMode: OverlayVisibilityMode.editing,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: passCtrl,
              placeholder: 'Password (Optional)',
              obscureText: true,
              clearButtonMode: OverlayVisibilityMode.editing,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Add'),
            onPressed: () {
              final host = hostCtrl.text.trim();
              final port = int.tryParse(portCtrl.text.trim()) ?? 1080;
              final user = userCtrl.text.trim();
              final pass = passCtrl.text.trim();

              if (host.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Host cannot be empty')),
                );
                return;
              }

              String uriStr = 'socks5://';
              if (user.isNotEmpty) {
                uriStr += '$user:$pass@';
              }
              uriStr += '$host:$port';

              final model = ProxyModel.fromUri(uriStr);
              if (model != null) {
                context.read<AppProxyProvider>().addProxy(model);
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid proxy parameters!')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showEditProxyDialog(BuildContext context, ProxyModel proxy) {
    final hostCtrl = TextEditingController(text: proxy.host);
    final portCtrl = TextEditingController(text: proxy.port.toString());
    final userCtrl = TextEditingController(text: proxy.username ?? '');
    final passCtrl = TextEditingController(text: proxy.password ?? '');

    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Edit Proxy'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: hostCtrl,
              placeholder: 'Host IP / Domain',
              clearButtonMode: OverlayVisibilityMode.editing,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: portCtrl,
              placeholder: 'Port',
              keyboardType: TextInputType.number,
              clearButtonMode: OverlayVisibilityMode.editing,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: userCtrl,
              placeholder: 'Username (Optional)',
              clearButtonMode: OverlayVisibilityMode.editing,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: passCtrl,
              placeholder: 'Password (Optional)',
              obscureText: true,
              clearButtonMode: OverlayVisibilityMode.editing,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Save'),
            onPressed: () {
              final host = hostCtrl.text.trim();
              final port = int.tryParse(portCtrl.text.trim()) ?? proxy.port;
              final user = userCtrl.text.trim();
              final pass = passCtrl.text.trim();

              if (host.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Host cannot be empty')),
                );
                return;
              }

              String uriStr = 'socks5://';
              if (user.isNotEmpty) {
                uriStr += '$user:$pass@';
              }
              uriStr += '$host:$port';

              final model = ProxyModel.fromUri(uriStr);
              if (model != null) {
                final updated = model.copyWith(
                  isActive: proxy.isActive,
                  latencyMs: proxy.latencyMs,
                );
                context.read<AppProxyProvider>().updateProxy(updated);
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid proxy parameters!')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _importYamlProxies(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (!path.endsWith('.yaml') && !path.endsWith('.yml')) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Please select a valid .yaml or .yml file')));
          }
          return;
        }
        final file = File(path);
        final yamlString = await file.readAsString();
        final Object? yamlDoc = loadYaml(yamlString);

        YamlList? proxyList;
        if (yamlDoc is YamlList) {
          proxyList = yamlDoc;
        } else if (yamlDoc is YamlMap) {
          final dynamic listValue = yamlDoc['proxies'];
          if (listValue is YamlList) {
            proxyList = listValue;
          }
        }

        if (proxyList != null) {
          int count = 0;
          for (var item in proxyList) {
            if (item is YamlMap) {
              String type = item['type']?.toString() ?? 'socks5';
              String ip =
                  item['ip']?.toString() ?? item['server']?.toString() ?? '';
              String port = item['port']?.toString() ?? '1080';
              String user = item['username']?.toString() ?? '';
              String pass = item['password']?.toString() ?? '';
              if (ip.isEmpty) continue;

              String uriStr = '$type://';
              if (user.isNotEmpty) uriStr += '$user:$pass@';
              uriStr += '$ip:$port';

              final model = ProxyModel.fromUri(uriStr);
              if (model != null) {
                if (context.mounted) {
                  context.read<AppProxyProvider>().addProxy(model);
                  count++;
                }
              }
            }
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Imported $count proxies from YAML')));
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Invalid YAML structure. Expected a list.')));
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error parsing YAML: $e')));
      }
    }
  }

  void _showBulkImportDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Bulk Import'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Paste one or more proxy URIs (one per line):',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: ctrl,
              maxLines: 6,
              placeholder: 'socks5://host:port\nsocks5://user:pass@host:port',
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Import'),
            onPressed: () async {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;

              final lines = text.split('\n');
              final proxies = <ProxyModel>[];
              for (var line in lines) {
                final cleaned = line.trim();
                if (cleaned.isEmpty) continue;
                final model = ProxyModel.fromUri(cleaned);
                if (model != null) {
                  proxies.add(model);
                }
              }

              if (proxies.isNotEmpty) {
                await context.read<AppProxyProvider>().addProxies(proxies);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Imported ${proxies.length} proxies!')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _exportConfiguration(BuildContext context, AppProxyProvider provider) {
    final proxies = provider.proxies;
    if (proxies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No proxies to export')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('# DirXplore Pro Proxy Configuration');
    buffer.writeln('# Exported ${DateTime.now().toIso8601String()}');
    buffer.writeln('proxies:');
    for (final p in proxies) {
      buffer.writeln('  - type: ${p.protocolString}');
      buffer.writeln('    server: ${p.host}');
      buffer.writeln('    port: ${p.port}');
      if (p.username != null && p.username!.isNotEmpty) {
        buffer.writeln('    username: ${p.username}');
        buffer.writeln('    password: ${p.password ?? ''}');
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuration copied to clipboard')),
    );
    Clipboard.setData(ClipboardData(text: buffer.toString()));
  }
}

class _AnimatedStatusDot extends StatefulWidget {
  final bool isConnected;

  const _AnimatedStatusDot({required this.isConnected});

  @override
  State<_AnimatedStatusDot> createState() => _AnimatedStatusDotState();
}

class _AnimatedStatusDotState extends State<_AnimatedStatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isConnected) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_AnimatedStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected && !oldWidget.isConnected) {
      _controller.repeat(reverse: true);
    } else if (!widget.isConnected && oldWidget.isConnected) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: widget.isConnected
                ? const Color(0xFF34C759).withValues(alpha: _animation.value)
                : Colors.grey.withValues(alpha: 0.4),
            shape: BoxShape.circle,
            boxShadow: widget.isConnected
                ? [
                    BoxShadow(
                      color: const Color(0xFF34C759).withValues(alpha: 0.4 * _animation.value),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}
