import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';

import 'maslaki_back_button.dart';
import 'maslaki_user_drawer.dart';

class MaslakiPageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;
  final Widget? endDrawer;
  final Widget? drawer;
  final bool showBackButton;
  final bool showDrawerButton;
  final int fallbackTabIndex;
  final bool centerTitle;
  final Color? backgroundColor;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final EdgeInsetsGeometry? bodyPadding;

  const MaslakiPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.endDrawer,
    this.drawer,
    this.showBackButton = true,
    this.showDrawerButton = true,
    this.fallbackTabIndex = 0,
    this.centerTitle = true,
    this.backgroundColor,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.bodyPadding,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedEndDrawer = endDrawer ?? const MaslakiUserDrawer();
    final leading = showBackButton
        ? MaslakiBackButton(fallbackTabIndex: fallbackTabIndex)
        : (showDrawerButton ? const MaslakiUserDrawerButton() : null);
    final content = bodyPadding == null
        ? body
        : Padding(padding: bodyPadding!, child: body);

    return Scaffold(
      extendBody: extendBody,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      backgroundColor: backgroundColor,
      drawer: drawer,
      endDrawer: resolvedEndDrawer,
      appBar: MaslakiTopBar(
        title: title,
        subtitle: subtitle,
        leading: leading,
        centerTitle: centerTitle,
        actions: actions,
      ),
      body: content,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      bottomSheet: bottomSheet,
    );
  }
}
