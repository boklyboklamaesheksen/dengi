import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../motion/glass.dart';
import '../motion/motion_curves.dart';
import '../motion/press_feedback.dart';
import '../widgets/play_prompts_host.dart';
import 'account_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';

/// Four-tab bottom navigation shell: VPN · Account · Support · Settings.
///
/// Tabs are kept alive via [IndexedStack] so returning to the VPN tab
/// instantly restores its state (connection timer, dial animations, scroll
/// position). The bar itself is a frosted pill anchored just above the
/// system gesture area.
class NavShell extends StatefulWidget {
  const NavShell({super.key});

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  int _index = 0;
  late final PageController _pageController;

  static const List<Widget> _pages = <Widget>[
    HomeScreen(),
    AccountScreen(),
    SupportScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onSelect(int i) {
    if (_index == i) return;
    setState(() => _index = i);
    _pageController.jumpToPage(i);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final List<_NavItem> items = <_NavItem>[
      _NavItem(
        label: l10n.tabHome,
        icon: Icons.shield_outlined,
        activeIcon: Icons.shield_rounded,
      ),
      _NavItem(
        label: l10n.tabAccount,
        icon: Icons.person_outline,
        activeIcon: Icons.person_rounded,
      ),
      _NavItem(
        label: l10n.tabSupport,
        icon: Icons.forum_outlined,
        activeIcon: Icons.forum_rounded,
      ),
      _NavItem(
        label: l10n.tabSettings,
        icon: Icons.tune_outlined,
        activeIcon: Icons.tune_rounded,
      ),
    ];

    return PlayPromptsHost(
      homeTabActive: _index == 0,
      child: Scaffold(
        backgroundColor: AppColors.base,
        extendBody: true,
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (int i) {
            if (_index != i) setState(() => _index = i);
          },
          children: _pages
              .map((Widget p) => _KeepAlivePage(child: p))
              .toList(),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: _NavBar(
            items: items,
            selected: _index,
            onSelect: _onSelect,
          ),
        ),
      ),
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});
  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<_NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return FrostedSurface(
      borderRadius: const BorderRadius.all(Radius.circular(26)),
      sigma: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < items.length; i++)
            Expanded(
              child: _NavTab(
                item: items[i],
                selected: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(20);
    // The label is wrapped in Flexible + FittedBox(scaleDown) so it
    // shrinks to fit narrow tab slots — without it the localised
    // "Поддержка" / "Настройки" labels overflowed the rounded pill on
    // smaller phones. ClipRect prevents the text bleeding outside the
    // tile during the AnimatedSize transition.
    final Widget content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          selected ? item.activeIcon : item.icon,
          size: 20,
          color: selected ? AppColors.emerald : AppColors.textSecondary,
        ),
        Flexible(
          child: ClipRect(
            child: AnimatedSize(
              duration: RabochiyDurations.tabSwitch,
              curve: RabochiyCurves.brisk,
              alignment: Alignment.centerLeft,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8, right: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(
                            color: AppColors.emerald,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );

    return PressScale(
      onTap: onTap,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: RabochiyDurations.tabSwitch,
        curve: RabochiyCurves.brisk,
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: radius),
        child: selected
            ? LiquidTile(
                borderRadius: radius,
                padding: EdgeInsets.zero,
                selected: true,
                accent: AppColors.emerald,
                elevated: false,
                child: Center(child: content),
              )
            : Center(child: content),
      ),
    );
  }
}
