import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../providers/browser_provider.dart';
import '../providers/download_provider.dart';
import '../providers/app_state.dart';
import '../models/directory_item.dart';
import '../services/proxy_tunnel.dart';
import '../services/haptic_service.dart';
import '../widgets/glass_card.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'media_player_screen.dart';
import 'download_preview_screen.dart';
import 'package:share_plus/share_plus.dart';

class BrowserTab extends StatefulWidget {
  const BrowserTab({super.key});

  @override
  State<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends State<BrowserTab>
    with TickerProviderStateMixin {
  final TextEditingController _urlCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = 'http://172.16.50.4/';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BrowserProvider>().loadUrl(_urlCtrl.text);
      }
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bs = context.watch<BrowserProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCount = bs.getSelectedItems().length;
    final showWebView = bs.isFallbackMode;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      drawerEdgeDragWidth: 20,
      drawer: _BrowserDrawer(
        urlCtrl: _urlCtrl,
        isDark: isDark,
        onClose: () => _scaffoldKey.currentState?.closeDrawer(),
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _CompactTopBar(
                  urlCtrl: _urlCtrl,
                  scaffoldKey: _scaffoldKey,
                  isDark: isDark,
                ),
                if (!showWebView && bs.breadcrumbs.isNotEmpty)
                  _BreadcrumbBar(
                    breadcrumbs: bs.breadcrumbs,
                    onTap: (i) {
                      HapticService.light();
                      bs.loadBreadcrumb(i);
                      _urlCtrl.text = bs.currentUrl;
                    },
                  ),
                Expanded(
                  child: showWebView
                      ? _WebViewBody(
                          bs: bs,
                          urlCtrl: _urlCtrl,
                          onShowOptions: (ctx, item) =>
                              _showItemOptions(ctx, item),
                        )
                      : _DirectoryBody(
                          bs: bs,
                          scrollCtrl: _scrollCtrl,
                          isDark: isDark,
                          onOpenItem: (item) {
                            HapticService.light();
                            if (item.isDirectory) {
                              _urlCtrl.text = item.url;
                              bs.loadUrl(item.url);
                            } else {
                              _showItemOptions(context, item);
                            }
                          },
                          onPlayMedia: _playMedia,
                          onShowOptions: (item) =>
                              _showItemOptions(context, item),
                          onToggleSelection: (item) {
                            HapticService.selection();
                            bs.toggleSelection(item);
                          },
                          onLongPress: (item) {
                            HapticService.medium();
                            bs.toggleSelection(item);
                          },
                        ),
                ),
              ],
            ),
            if (selectedCount > 0)
              _SelectionBar(
                count: selectedCount,
                isDark: isDark,
                onCancel: () => bs.selectAll(false),
                onDownload: () => _handleQueueDownload(bs),
              ),
          ],
        ),
      ),
    );
  }

  void _playMedia(BuildContext context, DirectoryItem item,
      List<DirectoryItem> allItems) {
    HapticService.selection();
    final videoFiles = allItems
        .where((i) => !i.isDirectory && _isPlayableMedia(i.name))
        .toList();
    final playlist = videoFiles
        .map((i) => <String, String>{
              'url': ProxyTunnel().getTunnelUrl(i.url),
              'title': i.name
            })
        .toList();
    final idx = videoFiles.indexWhere((i) => i.url == item.url);
    final safeIdx = idx >= 0 ? idx : 0;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => MediaPlayerScreen(
          url: playlist.isNotEmpty
              ? playlist[safeIdx]['url'] ?? item.url
              : item.url,
          title: item.name,
          playlist: playlist,
          initialIndex: safeIdx,
        ),
      ),
    );
  }

  Future<void> _handleQueueDownload(BrowserProvider bs) async {
    HapticService.medium();
    bool hasPermission = Platform.isIOS;
    if (!Platform.isIOS) {
      hasPermission = await Permission.manageExternalStorage.isGranted ||
          await Permission.storage.isGranted;
      if (!hasPermission) {
        final sm = await Permission.manageExternalStorage.request();
        final ss = await Permission.storage.request();
        if (sm.isGranted || ss.isGranted) hasPermission = true;
      }
    }
    if (!hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Storage permission is required to download files.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final dl = context.read<DownloadProvider>();
    final app = context.read<AppState>();
    final selected = bs.getSelectedItems();
    final List<DirectoryItem> files = [];

    for (var item in selected) {
      if (item.isDirectory) {
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );
        }
        final items = await dl.crawlFolder(item.url, item.name);
        if (context.mounted) Navigator.pop(context);
        if (context.mounted) {
          Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (_) => DownloadPreviewScreen(
                folderUrl: item.url,
                folderName: item.name,
                baseSaveDir: app.defaultSavePath,
                initialItems: items,
              ),
            ),
          );
        }
      } else {
        files.add(item);
      }
    }

    for (var item in files) {
      dl.addDownload(item.url, item.name, app.defaultSavePath);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${selected.length} items to queue')),
      );
    }
    bs.selectAll(false);
  }

  void _showItemOptions(BuildContext context, DirectoryItem item) {
    if (item.isDirectory) return;

    final isMedia = _isPlayableMedia(item.name);
    final bs = context.read<BrowserProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        message: Text(
          'Choose an action',
          style: TextStyle(
            fontSize: 12,
            color: (isDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.5),
          ),
        ),
        actions: [
          if (isMedia)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _playMedia(context, item, bs.items);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.play_fill,
                      color: CupertinoColors.activeBlue, size: 20),
                  SizedBox(width: 10),
                  Text('Play in App'),
                ],
              ),
            ),
          if (isMedia && (Platform.isAndroid || Platform.isIOS))
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                final tunnelUrl = ProxyTunnel().getTunnelUrl(item.url);
                if (Platform.isAndroid) {
                  try {
                    await AndroidIntent(
                      action: 'action_view',
                      package: 'org.videolan.vlc',
                      data: tunnelUrl,
                      type: 'video/*',
                      flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
                    ).launch();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'VLC could not be launched. Ensure it is installed.'),
                        ),
                      );
                    }
                  }
                } else if (Platform.isIOS) {
                  try {
                    const ch = MethodChannel('com.dirxplore/ios_download');
                    await ch.invokeMethod('openURL', {'url': item.url});
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('VLC for iOS is not installed.'),
                        ),
                      );
                    }
                  }
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.play,
                      color: CupertinoColors.activeOrange, size: 20),
                  SizedBox(width: 10),
                  Text('Play with VLC'),
                ],
              ),
            ),
          if (isMedia && Platform.isAndroid)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await AndroidIntent(
                    action: 'action_view',
                    package: 'com.mxtech.videoplayer.ad',
                    data: ProxyTunnel().getTunnelUrl(item.url),
                    type: 'video/*',
                    flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
                  ).launch();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'MX Player could not be launched. Ensure it is installed.'),
                      ),
                    );
                  }
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.play,
                      color: CupertinoColors.systemPurple, size: 20),
                  SizedBox(width: 10),
                  Text('Play with MX Player'),
                ],
              ),
            ),
          if (Platform.isAndroid)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await AndroidIntent(
                    action: 'action_view',
                    package: 'idm.internet.download.manager',
                    data: ProxyTunnel().getTunnelUrl(item.url),
                    flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
                  ).launch();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            '1DM could not be launched. Ensure it is installed.'),
                      ),
                    );
                  }
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.cloud_download,
                      color: CupertinoColors.activeGreen, size: 20),
                  SizedBox(width: 10),
                  Text('Download using 1DM'),
                ],
              ),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<BrowserProvider>().toggleSelection(item);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Selected, tap Queue Selected below to start'),
                ),
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.cloud_download_fill,
                    color: CupertinoColors.activeGreen, size: 20),
                SizedBox(width: 10),
                Text('Queue in App'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  bool _isPlayableMedia(String name) {
    return ['mp4', 'mkv', 'avi', 'mov', 'webm']
        .contains(name.split('.').last.toLowerCase());
  }
}

// ──────────────────────────────────────────────────────────────
// COMPACT PERSISTENT TOP BAR
// ──────────────────────────────────────────────────────────────

class _CompactTopBar extends StatelessWidget {
  final TextEditingController urlCtrl;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool isDark;

  const _CompactTopBar({
    required this.urlCtrl,
    required this.scaffoldKey,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bs = context.watch<BrowserProvider>();

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1C1C1E) : Colors.white)
                .withValues(alpha: 0.92),
            border: Border(
              bottom: BorderSide(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.1),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 2),
              // 1. Hamburger — opens side drawer
              _TopBarButton(
                icon: CupertinoIcons.line_horizontal_3,
                isDark: isDark,
                onTap: () {
                  HapticService.light();
                  scaffoldKey.currentState?.openDrawer();
                },
              ),
              // 2. Back
              _TopBarButton(
                icon: CupertinoIcons.chevron_back,
                isDark: isDark,
                enabled: bs.canGoBack,
                onTap: () {
                  if (bs.canGoBack) {
                    HapticService.light();
                    bs.goBack();
                    urlCtrl.text = bs.currentUrl;
                  }
                },
              ),
              // 3. Forward (placeholder — no forward stack in provider yet)
              _TopBarButton(
                icon: CupertinoIcons.chevron_forward,
                isDark: isDark,
                enabled: false,
                onTap: () {},
              ),
              // 4. Address field — always visible & centred
              Expanded(
                child: _InlineAddressBar(
                  controller: urlCtrl,
                  isDark: isDark,
                  onSubmitted: (v) {
                    HapticService.selection();
                    bs.loadUrl(v);
                  },
                ),
              ),
              // 5. Mode toggle: Directory Browser ↔ Normal Browser
              _TopBarButton(
                icon: bs.isFallbackMode
                    ? CupertinoIcons.globe
                    : CupertinoIcons.folder_fill,
                isDark: isDark,
                accent: true,
                accentColor: bs.isFallbackMode
                    ? CupertinoColors.activeBlue
                    : CupertinoColors.systemOrange,
                onTap: () {
                  HapticService.medium();
                  bs.toggleFallbackMode();
                },
              ),
              // 6. Refresh / Stop
              _TopBarButton(
                icon: bs.isLoading
                    ? CupertinoIcons.xmark_circle
                    : CupertinoIcons.arrow_clockwise,
                isDark: isDark,
                onTap: () {
                  HapticService.light();
                  bs.loadUrl(bs.currentUrl);
                },
              ),
              // 7. More (quick actions sheet)
              _TopBarButton(
                icon: CupertinoIcons.ellipsis,
                isDark: isDark,
                onTap: () => _showMoreSheet(context, bs),
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }

  void _showMoreSheet(BuildContext context, BrowserProvider bs) {
    final dark = isDark;
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: dark ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) {
                urlCtrl.text = data!.text!;
                if (context.mounted) bs.loadUrl(data.text!);
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.doc_on_clipboard,
                    color: CupertinoColors.activeBlue, size: 20),
                SizedBox(width: 10),
                Text('Paste & Go'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              if (context.mounted) {
                bs.toggleBookmark();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(bs.isCurrentBookmarked
                        ? 'Bookmark removed'
                        : 'Bookmark added'),
                  ),
                );
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  bs.isCurrentBookmarked
                      ? CupertinoIcons.star_fill
                      : CupertinoIcons.star,
                  color: CupertinoColors.systemYellow,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(bs.isCurrentBookmarked
                    ? 'Remove Bookmark'
                    : 'Add Bookmark'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              bs.toggleViewMode();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  bs.isGridView
                      ? CupertinoIcons.list_bullet
                      : CupertinoIcons.square_grid_2x2,
                  color: CupertinoColors.activeBlue,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(bs.isGridView ? 'Switch to List View' : 'Switch to Grid View'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              bs.toggleSort();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sort order changed')),
                );
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.arrow_up_arrow_down,
                    color: CupertinoColors.activeBlue, size: 20),
                SizedBox(width: 10),
                Text('Toggle Sort Order'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: bs.currentUrl));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('URL copied to clipboard')),
                );
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.doc_on_doc,
                    color: CupertinoColors.activeBlue, size: 20),
                SizedBox(width: 10),
                Text('Copy URL'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// TOP BAR BUTTON
// ──────────────────────────────────────────────────────────────

class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final bool enabled;
  final bool accent;
  final Color? accentColor;
  final VoidCallback onTap;

  const _TopBarButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
    this.enabled = true,
    this.accent = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (!enabled) {
      color = isDark ? Colors.white24 : Colors.black26;
    } else if (accent) {
      color = accentColor ?? CupertinoColors.activeBlue;
    } else {
      color = isDark ? Colors.white70 : Colors.black54;
    }

    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 54,
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(icon, size: 19, color: color, key: ValueKey(icon)),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// INLINE ADDRESS BAR
// ──────────────────────────────────────────────────────────────

class _InlineAddressBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final ValueChanged<String> onSubmitted;

  const _InlineAddressBar({
    required this.controller,
    required this.isDark,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          const SizedBox(width: 7),
          Icon(
            CupertinoIcons.lock_fill,
            size: 10,
            color: CupertinoColors.systemGreen.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: 'Enter URL',
              placeholderStyle: TextStyle(
                fontSize: 12,
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.25),
              ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
              decoration: null,
              padding: const EdgeInsets.symmetric(vertical: 0),
              clearButtonMode: OverlayVisibilityMode.editing,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onSubmitted: onSubmitted,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// BROWSER SIDE DRAWER
// ──────────────────────────────────────────────────────────────

class _BrowserDrawer extends StatelessWidget {
  final TextEditingController urlCtrl;
  final bool isDark;
  final VoidCallback onClose;

  const _BrowserDrawer({
    required this.urlCtrl,
    required this.isDark,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final bs = context.watch<BrowserProvider>();

    return Drawer(
      width: 280,
      backgroundColor:
          isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0A84FF), Color(0xFF30D158)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(CupertinoIcons.globe,
                        size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DirXplore',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        Text(
                          'Browser Menu',
                          style: TextStyle(
                            fontSize: 11,
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        size: 24,
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.08),
              height: 1,
              indent: 16,
              endIndent: 16,
            ),
            const SizedBox(height: 6),
            // ── Menu items ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _DrawerItem(
                    icon: CupertinoIcons.bookmark_fill,
                    label: 'Bookmarks',
                    subtitle: 'Manage bookmarks',
                    isDark: isDark,
                    color: CupertinoColors.systemYellow,
                    onTap: () {
                      onClose();
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (context.mounted) _showBookmarks(context, bs);
                      });
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.clock,
                    label: 'History',
                    subtitle: 'Browsing history',
                    isDark: isDark,
                    color: CupertinoColors.systemOrange,
                    onTap: () {
                      onClose();
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (context.mounted) _showHistory(context, bs);
                      });
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.search,
                    label: 'Find in Page',
                    subtitle: 'Search in current page',
                    isDark: isDark,
                    color: CupertinoColors.systemOrange,
                    onTap: () {
                      onClose();
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (context.mounted) _showFindInPage(context, bs);
                      });
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.share,
                    label: 'Share',
                    subtitle: 'Share current URL',
                    isDark: isDark,
                    color: CupertinoColors.activeBlue,
                    onTap: () {
                      onClose();
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (context.mounted) _showShare(context, bs);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBookmarks(BuildContext context, BrowserProvider bs) {
    final dark = isDark;
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final items = bs.bookmarks.toList();
          return CupertinoActionSheet(
            title: Text(
              'Bookmarks',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : Colors.black,
              ),
            ),
            actions: [
              if (items.isEmpty)
                CupertinoActionSheetAction(
                  isDefaultAction: true,
                  onPressed: () {},
                  child: Text(
                    'No bookmarks saved yet.\nTap ··· → Add Bookmark to save.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: (dark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                )
              else
                for (final b in items)
                  CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.pop(ctx);
                      urlCtrl.text = b['url']!;
                      bs.loadUrl(b['url']!);
                    },
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.bookmark_fill,
                            size: 18,
                            color: CupertinoColors.systemYellow),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b['name'] ?? 'Unknown',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15),
                              ),
                              Text(
                                b['url'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: (dark ? Colors.white : Colors.black)
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            bs.removeBookmark(b['url']!);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: const Icon(CupertinoIcons.trash,
                                size: 18,
                                color: CupertinoColors.destructiveRed),
                          ),
                        ),
                      ],
                    ),
                  ),
              CupertinoActionSheetAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showHistory(BuildContext context, BrowserProvider bs) {
    final dark = isDark;
    final crumbs = bs.breadcrumbs;
    final hasUrl = bs.currentUrl.isNotEmpty;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(
          'Navigation History',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: dark ? Colors.white : Colors.black,
          ),
        ),
        message: Text(
          hasUrl ? bs.currentUrl : 'No URL loaded',
          style: TextStyle(
            fontSize: 12,
            color: (dark ? Colors.white : Colors.black)
                .withValues(alpha: 0.45),
          ),
        ),
        actions: [
          if (bs.canGoBack)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                bs.goBack();
                urlCtrl.text = bs.currentUrl;
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.chevron_back,
                      color: CupertinoColors.activeBlue, size: 18),
                  SizedBox(width: 8),
                  Text('Go Back'),
                ],
              ),
            ),
          // Breadcrumb navigation
          if (crumbs.length > 1)
            for (int i = 0; i < crumbs.length; i++)
                CupertinoActionSheetAction(
                onPressed: i < crumbs.length - 1
                    ? () {
                        Navigator.pop(ctx);
                        bs.loadBreadcrumb(i);
                        urlCtrl.text = bs.currentUrl;
                      }
                    : () {},
                child: Row(
                  children: [
                    Icon(
                      i == 0
                          ? CupertinoIcons.globe
                          : CupertinoIcons.folder,
                      size: 16,
                      color: i < crumbs.length - 1
                          ? CupertinoColors.activeBlue
                          : (dark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.35),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        i == 0 ? '/${crumbs[i]}' : '/${crumbs[i]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: i < crumbs.length - 1
                              ? CupertinoColors.activeBlue
                              : (dark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    if (i < crumbs.length - 1)
                      Icon(
                        CupertinoIcons.chevron_forward,
                        size: 12,
                        color: (dark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.2),
                      ),
                  ],
                ),
              ),
          if (!bs.canGoBack && crumbs.length <= 1)
            CupertinoActionSheetAction(
              isDefaultAction: true,
              onPressed: () {},
              child: Text(
                hasUrl ? 'No earlier history.' : 'No URL loaded yet.',
                style: TextStyle(
                  fontSize: 13,
                  color: (dark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ),
    );
  }

  void _showFindInPage(BuildContext context, BrowserProvider bs) {
    final dark = isDark;
    final searchCtrl = TextEditingController();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final query = searchCtrl.text;
          final count = query.isNotEmpty
              ? bs.items
                  .where((i) =>
                      i.name.toLowerCase().contains(query.toLowerCase()))
                  .length
              : bs.items.length;
          return CupertinoActionSheet(
            title: Text(
              'Find in Page',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : Colors.black,
              ),
            ),
            message: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CupertinoTextField(
                controller: searchCtrl,
                placeholder: 'Type to filter items...',
                placeholderStyle: TextStyle(
                  fontSize: 14,
                  color: (dark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.35),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: dark ? Colors.white : Colors.black,
                ),
                decoration: BoxDecoration(
                  color: (dark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                clearButtonMode: OverlayVisibilityMode.editing,
                autofocus: true,
                onChanged: (v) {
                  bs.setSearchQuery(v);
                },
              ),
            ),
            actions: [
              CupertinoActionSheetAction(
                isDefaultAction: true,
                onPressed: () {
                  searchCtrl.dispose();
                  Navigator.pop(ctx);
                },
                child: Text(
                  query.isEmpty
                      ? 'Close'
                      : 'Close ($count matching)',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showShare(BuildContext context, BrowserProvider bs) {
    if (bs.currentUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No URL to share')),
      );
      return;
    }
    Share.share(
      bs.currentUrl,
      subject: 'Check this out',
    );
  }
}

// ──────────────────────────────────────────────────────────────
// DRAWER ITEM
// ──────────────────────────────────────────────────────────────

class _DrawerItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isDark;
  final Color color;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isDark,
    required this.color,
    required this.onTap,
  });

  @override
  State<_DrawerItem> createState() => _DrawerItemState();
}

class _DrawerItemState extends State<_DrawerItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          color: _pressed
              ? (widget.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(widget.icon, size: 16, color: widget.color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: (widget.isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.38),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 12,
              color: (widget.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.18),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// BREADCRUMB BAR
// ──────────────────────────────────────────────────────────────

class _BreadcrumbBar extends StatelessWidget {
  final List<String> breadcrumbs;
  final ValueChanged<int> onTap;

  const _BreadcrumbBar({
    required this.breadcrumbs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: breadcrumbs.length,
        separatorBuilder: (c, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            CupertinoIcons.chevron_right,
            size: 12,
            color: (isDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.3),
          ),
        ),
        itemBuilder: (context, index) {
          final isLast = index == breadcrumbs.length - 1;
          return GestureDetector(
            onTap: () => onTap(index),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isLast
                    ? CupertinoColors.activeBlue.withValues(alpha: 0.1)
                    : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  breadcrumbs[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isLast ? FontWeight.w600 : FontWeight.w400,
                    color: isLast
                        ? CupertinoColors.activeBlue
                        : (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// DIRECTORY BODY (loading, error, empty, list/grid)
// ──────────────────────────────────────────────────────────────

class _DirectoryBody extends StatefulWidget {
  final BrowserProvider bs;
  final ScrollController scrollCtrl;
  final bool isDark;
  final ValueChanged<DirectoryItem> onOpenItem;
  final void Function(BuildContext, DirectoryItem, List<DirectoryItem>)
      onPlayMedia;
  final ValueChanged<DirectoryItem> onShowOptions;
  final ValueChanged<DirectoryItem> onToggleSelection;
  final ValueChanged<DirectoryItem> onLongPress;

  const _DirectoryBody({
    required this.bs,
    required this.scrollCtrl,
    required this.isDark,
    required this.onOpenItem,
    required this.onPlayMedia,
    required this.onShowOptions,
    required this.onToggleSelection,
    required this.onLongPress,
  });

  @override
  State<_DirectoryBody> createState() => _DirectoryBodyState();
}

class _DirectoryBodyState extends State<_DirectoryBody>
    with SingleTickerProviderStateMixin {
  late AnimationController _appearCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQueryLocal = '';

  @override
  void initState() {
    super.initState();
    _appearCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _appearCtrl.forward();
    });
  }

  @override
  void didUpdateWidget(_DirectoryBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bs.items != widget.bs.items &&
        widget.bs.items.isNotEmpty) {
      _appearCtrl.reset();
      _appearCtrl.forward();
    }
  }

  @override
  void dispose() {
    _appearCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bs = widget.bs;

    if (bs.isLoading) {
      return _LoadingSkeleton(isDark: widget.isDark);
    }

    if (bs.errorMessage.isNotEmpty) {
      return _ErrorCard(
        message: bs.errorMessage,
        isDark: widget.isDark,
        onRetry: () => bs.loadUrl(bs.currentUrl),
        onCopyUrl: () {
          Clipboard.setData(ClipboardData(text: bs.currentUrl));
          HapticService.light();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('URL copied to clipboard')),
            );
          }
        },
      );
    }

    if (bs.items.isEmpty) {
      final hasQuery = _searchQueryLocal.isNotEmpty ||
          bs.selectedCategory != 'All Categories';
      return _EmptyState(
        hasQuery: hasQuery,
        isDark: widget.isDark,
        onRefresh: () => bs.loadUrl(bs.currentUrl),
      );
    }

    final dirs = bs.items.where((i) => i.isDirectory).length;
    final files = bs.items.where((i) => !i.isDirectory).length;
    double totalBytes = 0;
    for (var i in bs.items) {
      if (i.size != null) {
        try {
          final s = i.size!;
          if (s.endsWith('GB')) {
            totalBytes +=
                double.parse(s.replaceAll(' GB', '')) * 1073741824;
          } else if (s.endsWith('MB')) {
            totalBytes +=
                double.parse(s.replaceAll(' MB', '')) * 1048576;
          } else if (s.endsWith('KB')) {
            totalBytes += double.parse(s.replaceAll(' KB', '')) * 1024;
          }
        } catch (_) {}
      }
    }
    final totalSize = totalBytes >= 1073741824
        ? '${(totalBytes / 1073741824).toStringAsFixed(1)} GB'
        : totalBytes >= 1048576
            ? '${(totalBytes / 1048576).toStringAsFixed(1)} MB'
            : totalBytes >= 1024
                ? '${(totalBytes / 1024).toStringAsFixed(0)} KB'
                : totalBytes > 0
                    ? '${totalBytes.toInt()} B'
                    : null;

    final summary = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: GlassCard(
        borderRadius: 14,
        blurSigma: 20,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _statItem(CupertinoIcons.folder, '$dirs', 'Folders',
                CupertinoColors.activeBlue, widget.isDark),
            const SizedBox(width: 16),
            Container(
              width: 1,
              height: 32,
              color: (widget.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.08),
            ),
            const SizedBox(width: 16),
            _statItem(CupertinoIcons.doc, '$files', 'Files',
                CupertinoColors.activeGreen, widget.isDark),
            if (totalSize != null) ...[
              const Spacer(),
              Container(
                width: 1,
                height: 32,
                color: (widget.isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.08),
              ),
              const SizedBox(width: 16),
              _statItem(CupertinoIcons.tray_full, totalSize, 'Size',
                  CupertinoColors.systemOrange, widget.isDark),
            ],
          ],
        ),
      ),
    );

    // Search + Category row (moved from old header)
    final searchRow = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _GlassSearchField(
              controller: _searchCtrl,
              isDark: widget.isDark,
              onChanged: (v) {
                setState(() => _searchQueryLocal = v);
                bs.setSearchQuery(v);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _CategoryDropdown(
              value: bs.selectedCategory,
              categories: bs.categories,
              isDark: widget.isDark,
              onChanged: (v) {
                if (v != null) {
                  HapticService.selection();
                  bs.setCategory(v);
                }
              },
            ),
          ),
        ],
      ),
    );

    final chips = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: _FilterChips(
        currentCategory: bs.selectedCategory,
        categories: bs.categories.toList(),
        isDark: widget.isDark,
        onChanged: (cat) {
          HapticService.selection();
          bs.setCategory(cat);
        },
      ),
    );

    if (bs.isGridView) {
      return ListView(
        controller: widget.scrollCtrl,
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
        children: [
          summary,
          searchRow,
          chips,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.85,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: bs.items.length,
              itemBuilder: (context, index) {
                final item = bs.items[index];
                return _GridTile(
                  item: item,
                  isDark: widget.isDark,
                  searchQuery: _searchQueryLocal,
                  onTap: () => widget.onOpenItem(item),
                  onLongPress: () => widget.onLongPress(item),
                  onPlay: bs.items.any((i) =>
                          !i.isDirectory && _isPlayableMedia(i.name))
                      ? () => widget.onPlayMedia(context, item, bs.items)
                      : null,
                  onOptions: () => widget.onShowOptions(item),
                );
              },
            ),
          ),
        ],
      );
    }

    // Lazy list mode
    return ListView.builder(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
      itemCount: 3 + bs.items.length,
      itemBuilder: (context, index) {
        if (index == 0) return summary;
        if (index == 1) return searchRow;
        if (index == 2) return chips;
        final itemIndex = index - 3;
        final item = bs.items[itemIndex];
        return _AnimatedRow(
          index: itemIndex,
          animation: _appearCtrl,
          child: _FileRow(
            item: item,
            isDark: widget.isDark,
            searchQuery: _searchQueryLocal,
            onTap: () => widget.onOpenItem(item),
            onLongPress: () => widget.onLongPress(item),
            onPlay: bs.items.any((i) =>
                    !i.isDirectory && _isPlayableMedia(i.name))
                ? () => widget.onPlayMedia(context, item, bs.items)
                : null,
            onOptions: () => widget.onShowOptions(item),
            onToggleSelection: () => widget.onToggleSelection(item),
          ),
        );
      },
    );
  }

  Widget _statItem(
      IconData icon, String value, String label, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _isPlayableMedia(String name) {
    return ['mp4', 'mkv', 'avi', 'mov', 'webm']
        .contains(name.split('.').last.toLowerCase());
  }
}

class _AnimatedRow extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final Widget child;

  const _AnimatedRow({
    required this.index,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final delay = index * 0.03;
        final t =
            ((animation.value - delay) / (1.0 - delay)).clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 16 * (1.0 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

// ──────────────────────────────────────────────────────────────
// GLASS SEARCH FIELD
// ──────────────────────────────────────────────────────────────

class _GlassSearchField extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _GlassSearchField({
    required this.controller,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.search,
                size: 15,
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.4),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: CupertinoTextField(
                  controller: controller,
                  placeholder: 'Filter files...',
                  placeholderStyle: TextStyle(
                    fontSize: 12,
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.3),
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  decoration: null,
                  padding: EdgeInsets.zero,
                  clearButtonMode: OverlayVisibilityMode.editing,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// CATEGORY DROPDOWN
// ──────────────────────────────────────────────────────────────

class _CategoryDropdown extends StatelessWidget {
  final String value;
  final List<String> categories;
  final bool isDark;
  final ValueChanged<String?> onChanged;

  const _CategoryDropdown({
    required this.value,
    required this.categories,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.05),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              isDense: true,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              dropdownColor:
                  isDark ? const Color(0xFF1C1C1E) : Colors.white,
              items: categories.map((c) {
                return DropdownMenuItem(
                  value: c,
                  child: Text(c, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// FILTER CHIPS
// ──────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final String currentCategory;
  final List<String> categories;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _FilterChips({
    required this.currentCategory,
    required this.categories,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final selected = cat == currentCategory;
          return GestureDetector(
            onTap: () => onChanged(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? CupertinoColors.activeBlue.withValues(alpha: 0.15)
                    : (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: selected
                      ? CupertinoColors.activeBlue.withValues(alpha: 0.4)
                      : (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.06),
                ),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? CupertinoColors.activeBlue
                      : (isDark ? Colors.white60 : Colors.black54),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// FILE ROW (Apple Files style)
// ──────────────────────────────────────────────────────────────

class _FileRow extends StatelessWidget {
  final DirectoryItem item;
  final bool isDark;
  final String searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onPlay;
  final VoidCallback? onOptions;
  final VoidCallback? onToggleSelection;

  const _FileRow({
    required this.item,
    required this.isDark,
    required this.searchQuery,
    required this.onTap,
    required this.onLongPress,
    this.onPlay,
    this.onOptions,
    this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    final isMedia = _isPlayableMedia(item.name);
    final icon = item.isDirectory
        ? CupertinoIcons.folder
        : _iconFor(item.name);
    final color = item.isDirectory
        ? CupertinoColors.activeBlue
        : _colorFor(item.name);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 62,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        decoration: BoxDecoration(
          color: item.isSelected
              ? CupertinoColors.activeBlue.withValues(alpha: 0.12)
              : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlightedText(
                    item.name,
                    searchQuery,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    highlightStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.activeBlue,
                      backgroundColor:
                          CupertinoColors.activeBlue.withValues(alpha: 0.12),
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (item.size != null &&
                          item.size!.isNotEmpty) ...[
                        Text(
                          item.size!,
                          style: TextStyle(
                            fontSize: 11,
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.25),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        item.typeTag,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: color.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isMedia && !item.isDirectory) ...[
              if (onPlay != null)
                Semantics(
                  label: 'Play ${item.name}',
                  child: GestureDetector(
                    onTap: onPlay,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      child: const Icon(CupertinoIcons.play_fill,
                          size: 18,
                          color: CupertinoColors.activeBlue),
                    ),
                  ),
                ),
              if (onOptions != null)
                GestureDetector(
                  onTap: onOptions,
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    child: Icon(
                      CupertinoIcons.ellipsis,
                      size: 16,
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ),
            ],
            if (onToggleSelection != null)
              GestureDetector(
                onTap: onToggleSelection,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: item.isSelected
                          ? CupertinoColors.activeBlue
                          : Colors.transparent,
                      border: Border.all(
                        color: item.isSelected
                            ? CupertinoColors.activeBlue
                            : (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: item.isSelected
                        ? const Icon(CupertinoIcons.check_mark,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  bool _isPlayableMedia(String name) {
    return ['mp4', 'mkv', 'avi', 'mov', 'webm']
        .contains(name.split('.').last.toLowerCase());
  }

  Widget _highlightedText(
    String text,
    String query, {
    required TextStyle style,
    required TextStyle highlightStyle,
    int maxLines = 1,
  }) {
    if (query.isEmpty) {
      return Text(text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style);
    }
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) {
      return Text(text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style);
    }
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          if (idx > 0) TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + q.length),
            style: highlightStyle,
          ),
          if (idx + q.length < text.length)
            TextSpan(text: text.substring(idx + q.length)),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// GRID TILE
// ──────────────────────────────────────────────────────────────

class _GridTile extends StatelessWidget {
  final DirectoryItem item;
  final bool isDark;
  final String searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onPlay;
  final VoidCallback? onOptions;

  const _GridTile({
    required this.item,
    required this.isDark,
    required this.searchQuery,
    required this.onTap,
    required this.onLongPress,
    this.onPlay,
    this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    final isMedia = _isPlayableMedia(item.name);
    final icon =
        item.isDirectory ? CupertinoIcons.folder : _iconFor(item.name);
    final color = item.isDirectory
        ? CupertinoColors.activeBlue
        : _colorFor(item.name);
    final isImage = !item.isDirectory &&
        ['jpg', 'jpeg', 'png', 'gif', 'webp']
            .contains(item.name.split('.').last.toLowerCase());

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: item.isSelected
              ? CupertinoColors.activeBlue.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: item.isSelected
                ? CupertinoColors.activeBlue.withValues(alpha: 0.4)
                : (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: isImage
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          image: DecorationImage(
                            image: NetworkImage(item.url),
                            fit: BoxFit.cover,
                            onError: (_, __) {},
                          ),
                        )
                      : BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                  child:
                      isImage ? null : Icon(icon, size: 26, color: color),
                ),
                if (item.isSelected)
                  Positioned(
                    right: 4,
                    top: 8,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: CupertinoColors.activeBlue,
                      ),
                      child: const Icon(CupertinoIcons.check_mark,
                          size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            if (item.size != null && item.size!.isNotEmpty)
              Text(
                item.size!,
                style: TextStyle(
                  fontSize: 10,
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.4),
                ),
              ),
            if (isMedia && !item.isDirectory) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onPlay != null)
                    GestureDetector(
                      onTap: onPlay,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: CupertinoColors.activeBlue
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(CupertinoIcons.play_fill,
                            size: 14,
                            color: CupertinoColors.activeBlue),
                      ),
                    ),
                  if (onPlay != null && onOptions != null)
                    const SizedBox(width: 8),
                  if (onOptions != null)
                    GestureDetector(
                      onTap: onOptions,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(CupertinoIcons.ellipsis,
                            size: 14,
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.4)),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isPlayableMedia(String name) {
    return ['mp4', 'mkv', 'avi', 'mov', 'webm']
        .contains(name.split('.').last.toLowerCase());
  }
}

// ──────────────────────────────────────────────────────────────
// LOADING SKELETON
// ──────────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatefulWidget {
  final bool isDark;
  const _LoadingSkeleton({required this.isDark});

  @override
  State<_LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<_LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = (widget.isDark ? Colors.white : Colors.black)
        .withValues(alpha: 0.06);
    final highlight = (widget.isDark ? Colors.white : Colors.black)
        .withValues(alpha: 0.1);

    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (context, child) {
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
          itemCount: 10,
          itemBuilder: (context, index) {
            final phase = ((index * 0.15 + _shimmerCtrl.value) % 1.0);
            final color = Color.lerp(base, highlight, phase)!;
            return Container(
              height: 62,
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 200 * (0.5 + (index % 5) * 0.1),
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 100,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────
// ERROR CARD
// ──────────────────────────────────────────────────────────────

class _ErrorCard extends StatefulWidget {
  final String message;
  final bool isDark;
  final VoidCallback onRetry;
  final VoidCallback onCopyUrl;

  const _ErrorCard({
    required this.message,
    required this.isDark,
    required this.onRetry,
    required this.onCopyUrl,
  });

  @override
  State<_ErrorCard> createState() => _ErrorCardState();
}

class _ErrorCardState extends State<_ErrorCard> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          borderRadius: 20,
          blurSigma: 20,
          padding: const EdgeInsets.all(24),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: CupertinoColors.destructiveRed
                    .withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  size: 48,
                  color: CupertinoColors.destructiveRed
                      .withValues(alpha: 0.7),
                ),
                const SizedBox(height: 16),
                Text(
                  'Connection Error',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: widget.isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: (widget.isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () =>
                      setState(() => _showDetails = !_showDetails),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _showDetails
                            ? 'Hide technical details'
                            : 'Show technical details',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.activeBlue,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _showDetails
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 12,
                        color: CupertinoColors.activeBlue,
                      ),
                    ],
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (widget.isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        widget.message,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color:
                              (widget.isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  crossFadeState: _showDetails
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CupertinoButton.filled(
                      borderRadius: BorderRadius.circular(12),
                      onPressed: widget.onRetry,
                      child: const Text('Retry'),
                    ),
                    const SizedBox(width: 12),
                    CupertinoButton(
                      borderRadius: BorderRadius.circular(12),
                      onPressed: widget.onCopyUrl,
                      child: const Text('Copy URL'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// EMPTY STATE
// ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  final bool isDark;
  final VoidCallback onRefresh;

  const _EmptyState({
    required this.hasQuery,
    required this.isDark,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery
                  ? CupertinoIcons.search
                  : CupertinoIcons.folder_open,
              size: 56,
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.15),
            ),
            const SizedBox(height: 16),
            Text(
              hasQuery ? 'No Results' : 'No Files Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? 'Try adjusting your search or filter.'
                  : 'This directory doesn\'t contain any downloadable items.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.5),
              ),
            ),
            if (!hasQuery) ...[
              const SizedBox(height: 24),
              CupertinoButton(
                borderRadius: BorderRadius.circular(12),
                onPressed: onRefresh,
                child: const Text('Refresh'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// SELECTION BAR
// ──────────────────────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  final int count;
  final bool isDark;
  final VoidCallback onCancel;
  final VoidCallback onDownload;

  const _SelectionBar({
    required this.count,
    required this.isDark,
    required this.onCancel,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF1C1C1E) : Colors.white)
                    .withValues(alpha: 0.85),
                border: Border(
                  top: BorderSide(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onCancel,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(
                        CupertinoIcons.clear_circled,
                        size: 22,
                        color: CupertinoColors.destructiveRed,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$count selected',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    borderRadius: BorderRadius.circular(12),
                    onPressed: onDownload,
                    child: const Text('Queue Download'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// WEB VIEW BODY
// ──────────────────────────────────────────────────────────────

class _WebViewBody extends StatelessWidget {
  final BrowserProvider bs;
  final TextEditingController urlCtrl;
  final void Function(BuildContext, DirectoryItem) onShowOptions;

  const _WebViewBody({
    required this.bs,
    required this.urlCtrl,
    required this.onShowOptions,
  });

  @override
  Widget build(BuildContext context) {
    final initialUrl = bs.currentUrl.isNotEmpty
        ? WebUri(bs.currentUrl)
        : WebUri('http://new.circleftp.net/');

    const mediaExtensions = [
      'mp4', 'mkv', 'avi', 'mov', 'webm', 'mp3', 'flac', 'wav'
    ];
    const downloadExtensions = [
      'zip', 'rar', '7z', 'tar', 'gz', 'apk', 'pdf', 'iso', 'img'
    ];

    return InAppWebView(
      key: ValueKey(initialUrl.toString()),
      initialUrlRequest: URLRequest(url: initialUrl),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useShouldOverrideUrlLoading: true,
        useOnDownloadStart: true,
        userAgent:
            'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36',
      ),
      onWebViewCreated: (controller) {},
      onLoadStart: (controller, url) {
        if (url != null) urlCtrl.text = url.toString();
      },
      onLoadStop: (controller, url) async {
        if (url != null) urlCtrl.text = url.toString();
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        final ext = url.split('?').first.split('.').last.toLowerCase();

        if (mediaExtensions.contains(ext) ||
            downloadExtensions.contains(ext)) {
          final name = Uri.parse(url).pathSegments.lastWhere(
              (s) => s.isNotEmpty,
              orElse: () => 'file');
          final item = DirectoryItem(
            name: name,
            url: url,
            type: DirectoryItem.typeFromExtension(name),
            size: null,
          );
          if (context.mounted) onShowOptions(context, item);
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onDownloadStartRequest: (controller, request) {
        final url = request.url.toString();
        final name = Uri.parse(url).pathSegments.lastWhere(
            (s) => s.isNotEmpty,
            orElse: () => 'file');
        final item = DirectoryItem(
          name: name,
          url: url,
          type: DirectoryItem.typeFromExtension(name),
          size: null,
        );
        if (context.mounted) onShowOptions(context, item);
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────
// HELPERS
// ──────────────────────────────────────────────────────────────

IconData _iconFor(String name) {
  final ext = name.split('.').last.toLowerCase();
  if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) {
    return CupertinoIcons.film;
  }
  if (['mp3', 'wav', 'flac'].contains(ext)) {
    return CupertinoIcons.music_note;
  }
  if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
    return CupertinoIcons.photo;
  }
  if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
    return CupertinoIcons.archivebox;
  }
  if (['apk'].contains(ext)) {
    return CupertinoIcons.gear;
  }
  if (['pdf', 'doc', 'docx', 'txt', 'epub'].contains(ext)) {
    return CupertinoIcons.doc_text;
  }
  if (['ipa'].contains(ext)) {
    return CupertinoIcons.gear;
  }
  if (['torrent'].contains(ext)) {
    return CupertinoIcons.link;
  }
  if (['exe', 'msi', 'dmg'].contains(ext)) {
    return CupertinoIcons.gear;
  }
  if (['iso', 'img'].contains(ext)) {
    return CupertinoIcons.archivebox;
  }
  if (['srt', 'sub', 'ass', 'vtt'].contains(ext)) {
    return CupertinoIcons.captions_bubble;
  }
  return CupertinoIcons.doc;
}

Color _colorFor(String name) {
  final ext = name.split('.').last.toLowerCase();
  if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) {
    return CupertinoColors.systemPurple;
  }
  if (['mp3', 'wav', 'flac'].contains(ext)) {
    return CupertinoColors.systemOrange;
  }
  if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
    return CupertinoColors.systemGreen;
  }
  if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
    return CupertinoColors.systemRed;
  }
  if (['apk', 'ipa'].contains(ext)) {
    return CupertinoColors.systemGreen;
  }
  if (['pdf', 'doc', 'docx', 'epub'].contains(ext)) {
    return CupertinoColors.systemBlue;
  }
  if (['torrent'].contains(ext)) {
    return CupertinoColors.systemTeal;
  }
  if (['exe', 'dmg'].contains(ext)) {
    return CupertinoColors.systemIndigo;
  }
  if (['iso', 'img'].contains(ext)) {
    return CupertinoColors.systemRed;
  }
  if (['srt', 'sub', 'ass'].contains(ext)) {
    return CupertinoColors.systemGrey;
  }
  return CupertinoColors.systemGrey;
}
