import 'package:flutter/material.dart';

import '../../features/customer/ui/maslaki_user_shell.dart';
import '../i18n/app_localizations_context.dart';

class MaslakiBackButton extends StatelessWidget {
  final Color? color;
  final String? tooltip;
  final int fallbackTabIndex;
  final IconData icon;

  const MaslakiBackButton({
    super.key,
    this.color,
    this.tooltip,
    this.fallbackTabIndex = 0,
    this.icon = Icons.arrow_back_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip ?? context.l10n.commonBack,
      onPressed: () => MaslakiHomeNavigator.maybePopOrGoHome(
        context,
        fallbackTabIndex: fallbackTabIndex,
      ),
      icon: Icon(icon, color: color),
    );
  }
}
