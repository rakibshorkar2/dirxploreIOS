import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import '../services/haptic_service.dart';

class PremiumBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const PremiumBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<PremiumBottomNav> createState() => _PremiumBottomNavState();
}

class _PremiumBottomNavState extends State<PremiumBottomNav>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  static const List<_NavItem> _navItems = [
    _NavItem(
      icon: CupertinoIcons.compass,
      activeIcon: CupertinoIcons.compass_fill,
      label: 'Browser',
      semanticLabel: 'Browse files and directories',
    ),
    _NavItem(
      icon: CupertinoIcons.arrow_down_circle,
      activeIcon: CupertinoIcons.arrow_down_circle_fill,
      label: 'Downloads',
      semanticLabel: 'View downloads',
    ),
    _NavItem(
      icon: CupertinoIcons.shield,
      activeIcon: CupertinoIcons.shield_fill,
      label: 'Proxy',
      semanticLabel: 'Proxy settings',
    ),
    _NavItem(
      icon: CupertinoIcons.settings,
      activeIcon: CupertinoIcons.settings_solid,
      label: 'Settings',
      semanticLabel: 'App settings',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _pulseController.value = 1.0;
  }

  @override
  void didUpdateWidget(PremiumBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _pulseController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final activeColor = isDark ? Colors.white : cs.primary;
    final inactiveColor = (isDark ? Colors.white : cs.onSurface)
        .withValues(alpha: 0.3);

    return Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        bottom: bottomPadding + 6,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: isDark ? 0.1 : 0.05),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: isDark ? 0.06 : 0.04),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: List.generate(_navItems.length, (index) {
                final isSelected = index == widget.currentIndex;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticService.light();
                      widget.onTap(index);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Semantics(
                      label: _navItems[index].semanticLabel,
                      selected: isSelected,
                      child: Container(
                        height: 58,
                        alignment: Alignment.center,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, _) {
                            final pulse = isSelected
                                ? 1.0 +
                                    (_pulseController.value * 0.035 -
                                        _pulseController.value *
                                            _pulseController.value *
                                            0.035)
                                : 1.0;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: isSelected
                                        ? (isDark
                                                ? Colors.white
                                                : cs.primary)
                                            .withValues(
                                                alpha: isDark ? 0.12 : 0.10)
                                        : Colors.transparent,
                                  ),
                                  child: Transform.scale(
                                    scale: pulse,
                                    child: Icon(
                                      isSelected
                                          ? _navItems[index].activeIcon
                                          : _navItems[index].icon,
                                      size: 23,
                                      key: ValueKey<int>(
                                        isSelected ? 1 : 0,
                                      ),
                                      color: isSelected
                                          ? activeColor
                                          : inactiveColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  _navItems[index].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.1,
                                    color: isSelected
                                        ? activeColor
                                        : inactiveColor,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String semanticLabel;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.semanticLabel,
  });
}
