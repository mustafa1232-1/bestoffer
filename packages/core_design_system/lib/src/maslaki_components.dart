import 'package:flutter/material.dart';

import 'app_theme.dart';

class MaslakiScreenFrame extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool scrollable;
  final String? title;
  final String? subtitle;
  final Widget? headerTrailing;

  const MaslakiScreenFrame({
    super.key,
    required this.child,
    this.padding,
    this.scrollable = false,
    this.title,
    this.subtitle,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final shell = context.maslakiShell;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((title ?? '').trim().isNotEmpty || headerTrailing != null)
          Padding(
            padding: const EdgeInsets.only(bottom: MaslakiSpacing.lg),
            child: Row(
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (headerTrailing != null) ...[
                  headerTrailing!,
                  const SizedBox(width: MaslakiSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if ((title ?? '').trim().isNotEmpty)
                        Text(
                          title!,
                          textDirection: TextDirection.rtl,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      if ((subtitle ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          textDirection: TextDirection.rtl,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        child,
      ],
    );

    final wrapped = Padding(
      padding:
          padding ??
          EdgeInsets.fromLTRB(
            shell.outerPadding,
            shell.outerPadding,
            shell.outerPadding,
            shell.outerPadding,
          ),
      child: content,
    );

    if (scrollable) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        children: [wrapped],
      );
    }
    return wrapped;
  }
}

class MaslakiCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;
  final bool elevated;
  final Color? backgroundColor;
  final Color? borderColor;
  final Gradient? gradient;

  const MaslakiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MaslakiSpacing.md),
    this.radius,
    this.elevated = true,
    this.backgroundColor,
    this.borderColor,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final shell = context.maslakiShell;
    final visual = context.visualTheme;
    return AnimatedContainer(
      duration: context.maslakiMotion.normal,
      curve: context.maslakiMotion.emphasizedCurve,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? shell.cardRadius),
        color: backgroundColor ?? tokens.cardPrimary.withValues(alpha: 0.94),
        gradient: gradient,
        border: Border.all(
          color:
              borderColor ??
              tokens.borderSubtle.withValues(alpha: elevated ? 1 : 0.74),
        ),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: visual.accentGold.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ]
            : const [],
      ),
      child: child,
    );
  }
}

class MaslakiSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final String? subtitle;

  const MaslakiSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onActionTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Row(
      textDirection: TextDirection.rtl,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((actionLabel ?? '').trim().isNotEmpty)
          TextButton(onPressed: onActionTap, child: Text(actionLabel!)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                title,
                textDirection: TextDirection.rtl,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              if ((subtitle ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class MaslakiTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final bool centerTitle;
  final Widget? badge;

  const MaslakiTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.centerTitle = true,
    this.badge,
  });

  @override
  Size get preferredSize => const Size.fromHeight(82);

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    return AppBar(
      toolbarHeight: 82,
      centerTitle: centerTitle,
      leading: leading,
      titleSpacing: 18,
      title: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: centerTitle
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: centerTitle
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null) ...[badge!, const SizedBox(width: 8)],
              // Flexible + single-line ellipsis so a long store name never
              // overflows the app bar (it shrinks to the available width).
              Flexible(
                child: Text(
                  title,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if ((subtitle ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: visual.accentCyan.withValues(alpha: 0.84),
              ),
            ),
          ],
        ],
      ),
      actions: [...actions, const SizedBox(width: 6)],
    );
  }
}

class MaslakiSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool readOnly;
  final Widget? trailing;

  const MaslakiSearchField({
    super.key,
    this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final shell = context.maslakiShell;
    return MaslakiCard(
      elevated: false,
      radius: shell.fieldRadius,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      backgroundColor: tokens.surfaceSecondary.withValues(alpha: 0.76),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onTap: onTap,
        readOnly: readOnly,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(Icons.search_rounded, color: tokens.primaryAccent),
          suffixIcon: trailing,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class MaslakiPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  const MaslakiPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? ElevatedButton(
            onPressed: onPressed,
            child: Text(label, textDirection: TextDirection.rtl),
          )
        : ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label, textDirection: TextDirection.rtl),
          );
    if (!expanded) return child;
    return SizedBox(width: double.infinity, child: child);
  }
}

class MaslakiOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const MaslakiOutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? OutlinedButton(
            onPressed: onPressed,
            child: Text(label, textDirection: TextDirection.rtl),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label, textDirection: TextDirection.rtl),
          );
    return SizedBox(width: double.infinity, child: child);
  }
}

class MaslakiStatusPill extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;

  const MaslakiStatusPill({
    super.key,
    required this.label,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    final resolved = color ?? visual.accentGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: resolved.withValues(alpha: 0.12),
        border: Border.all(color: resolved.withValues(alpha: 0.44)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: resolved),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color == null ? tokens.textPrimary : resolved,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class MaslakiChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;

  const MaslakiChip({
    super.key,
    required this.label,
    this.selected = false,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(context.maslakiShell.chipRadius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: context.maslakiMotion.normal,
        curve: context.maslakiMotion.emphasizedCurve,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.maslakiShell.chipRadius),
          color: selected
              ? tokens.primaryAccent.withValues(alpha: 0.18)
              : tokens.surfaceSecondary.withValues(alpha: 0.64),
          border: Border.all(
            color: selected
                ? tokens.primaryAccent.withValues(alpha: 0.76)
                : tokens.borderSubtle.withValues(alpha: 0.84),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? tokens.primaryAccent : visual.accentCyan,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? tokens.primaryAccent : tokens.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MaslakiOfferBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onTap;

  const MaslakiOfferBanner({
    super.key,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(context.maslakiShell.cardRadius),
      onTap: onTap,
      child: MaslakiCard(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            tokens.surfacePrimary,
            tokens.cardElevated,
            tokens.backgroundSecondary,
          ],
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              start: -16,
              bottom: -28,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      visual.accentGold.withValues(alpha: 0.28),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if ((ctaLabel ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: MaslakiStatusPill(
                      label: ctaLabel!,
                      color: visual.accentGold,
                      icon: Icons.arrow_back_rounded,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MaslakiMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const MaslakiMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return MaslakiCard(
      padding: const EdgeInsets.all(MaslakiSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Icon(icon, color: tokens.primaryAccent),
          ),
          const SizedBox(height: MaslakiSpacing.md),
          Text(
            value,
            textDirection: TextDirection.rtl,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textDirection: TextDirection.rtl,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class MaslakiListRowCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData leadingIcon;
  final Widget? trailing;
  final VoidCallback? onTap;

  const MaslakiListRowCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.leadingIcon,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return InkWell(
      borderRadius: BorderRadius.circular(context.maslakiShell.fieldRadius),
      onTap: onTap,
      child: MaslakiCard(
        elevated: false,
        radius: context.maslakiShell.fieldRadius,
        padding: const EdgeInsets.symmetric(
          horizontal: MaslakiSpacing.md,
          vertical: MaslakiSpacing.sm,
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: MaslakiSpacing.sm),
            ] else ...[
              Icon(
                Icons.arrow_back_ios_new_rounded,
                color: tokens.textMuted,
                size: 16,
              ),
              const SizedBox(width: MaslakiSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    title,
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if ((subtitle ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: MaslakiSpacing.md),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.primaryAccent.withValues(alpha: 0.12),
                border: Border.all(
                  color: tokens.primaryAccent.withValues(alpha: 0.32),
                ),
              ),
              child: Icon(leadingIcon, color: tokens.primaryAccent, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class MaslakiBottomNavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int badgeCount;

  const MaslakiBottomNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badgeCount = 0,
  });
}

class MaslakiBottomNavShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<MaslakiBottomNavItem> items;
  final bool visible;

  const MaslakiBottomNavShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    final shell = context.maslakiShell;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1.2),
      duration: context.maslakiMotion.normal,
      curve: context.maslakiMotion.emphasizedCurve,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: context.maslakiMotion.fast,
        child: Container(
          height: shell.bottomNavHeight + bottomInset,
          padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomInset),
          decoration: BoxDecoration(
            color: tokens.surfacePrimary.withValues(alpha: 0.985),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(shell.navRadius),
              topRight: Radius.circular(shell.navRadius),
            ),
            border: Border(
              top: BorderSide(
                color: tokens.borderSubtle.withValues(alpha: 0.96),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: visual.accentGold.withValues(alpha: 0.08),
                blurRadius: 22,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = index == currentIndex;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(shell.chipRadius),
                  onTap: () => onTap(index),
                  child: AnimatedContainer(
                    duration: context.maslakiMotion.normal,
                    curve: context.maslakiMotion.emphasizedCurve,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(shell.chipRadius),
                      gradient: selected
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                tokens.primaryAccent.withValues(alpha: 0.16),
                                Colors.transparent,
                              ],
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              selected ? item.activeIcon : item.icon,
                              color: selected
                                  ? tokens.primaryAccent
                                  : tokens.textMuted,
                              size: 22,
                            ),
                            if (item.badgeCount > 0)
                              PositionedDirectional(
                                end: -7,
                                top: -6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tokens.danger,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: tokens.backgroundPrimary,
                                    ),
                                  ),
                                  child: Text(
                                    item.badgeCount > 99
                                        ? '99+'
                                        : '${item.badgeCount}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: tokens.textPrimary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: selected
                                    ? tokens.primaryAccent
                                    : tokens.textMuted,
                                fontWeight: selected
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class MaslakiEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  const MaslakiEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: MaslakiCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.primaryAccent.withValues(alpha: 0.12),
                  border: Border.all(
                    color: tokens.primaryAccent.withValues(alpha: 0.34),
                  ),
                ),
                child: Icon(icon, color: tokens.primaryAccent, size: 28),
              ),
              const SizedBox(height: MaslakiSpacing.md),
              Text(
                title,
                textDirection: TextDirection.rtl,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textDirection: TextDirection.rtl,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: MaslakiSpacing.md),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
