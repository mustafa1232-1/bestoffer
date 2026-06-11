import 'package:flutter/material.dart';

/// يربط أسماء الحقول بمفاتيح عرض و`FocusNode` حتى تستطيع الصفحة تحريك
/// المستخدم مباشرة إلى أول حقل خاطئ بدلاً من إبقائه في أسفل الشاشة.
class FormScrollCoordinator {
  final Map<String, GlobalKey> _anchors = <String, GlobalKey>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};

  GlobalKey anchorKeyFor(String field) =>
      _anchors.putIfAbsent(field, GlobalKey.new);

  FocusNode focusNodeFor(String field) =>
      _focusNodes.putIfAbsent(field, FocusNode.new);

  Widget anchor(String field, Widget child) {
    return KeyedSubtree(key: anchorKeyFor(field), child: child);
  }

  Future<void> focusFirstError(
    Iterable<String> orderedFields, {
    Duration duration = const Duration(milliseconds: 260),
  }) async {
    for (final field in orderedFields) {
      final context = _anchors[field]?.currentContext;
      if (context != null) {
        await Scrollable.ensureVisible(
          context,
          duration: duration,
          alignment: 0.18,
          curve: Curves.easeOutCubic,
        );
      }

      final focusNode = _focusNodes[field];
      if (focusNode != null && focusNode.canRequestFocus) {
        focusNode.requestFocus();
      }

      if (context != null || focusNode != null) {
        return;
      }
    }
  }

  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();
    _anchors.clear();
  }
}
