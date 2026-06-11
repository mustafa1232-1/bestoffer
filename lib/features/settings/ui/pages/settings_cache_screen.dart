import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/media_cache_service.dart';

class SettingsCacheScreen extends ConsumerStatefulWidget {
  const SettingsCacheScreen({super.key});

  @override
  ConsumerState<SettingsCacheScreen> createState() =>
      _SettingsCacheScreenState();
}

class _SettingsCacheScreenState extends ConsumerState<SettingsCacheScreen> {
  bool _loading = true;
  bool _clearing = false;
  int _imageBytes = 0;
  int _videoBytes = 0;
  int _totalBytes = 0;

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final stats = await ref.read(mediaCacheServiceProvider).getStats();
    if (!mounted) return;
    setState(() {
      _imageBytes = stats.imageBytes;
      _videoBytes = stats.videoBytes;
      _totalBytes = stats.totalBytes;
      _loading = false;
    });
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_isArabic ? 'مسح الملفات المؤقتة' : 'Clear cached media'),
          content: Text(
            _isArabic
                ? 'سيتم حذف الصور والفيديوهات المخزنة مؤقتاً من الجهاز.'
                : 'This removes cached images and videos from the device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_isArabic ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_isArabic ? 'مسح' : 'Clear'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _clearing = true);
    await ref.read(mediaCacheServiceProvider).clearAllCaches();
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    setState(() => _clearing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isArabic
              ? 'تم مسح الملفات المؤقتة بنجاح'
              : 'Cached media cleared successfully',
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return _isArabic ? '0 بايت' : '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final formatted = value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    if (_isArabic && units[unitIndex] == 'B') {
      return '$formatted بايت';
    }
    return '$formatted ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isArabic ? 'الملفات المؤقتة' : 'Cached media'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _CacheRow(
                            label: _isArabic ? 'الصور' : 'Images',
                            value: _formatBytes(_imageBytes),
                          ),
                          const SizedBox(height: 8),
                          _CacheRow(
                            label: _isArabic ? 'الفيديوهات' : 'Videos',
                            value: _formatBytes(_videoBytes),
                          ),
                          const Divider(height: 22),
                          _CacheRow(
                            label: _isArabic ? 'الإجمالي' : 'Total',
                            value: _formatBytes(_totalBytes),
                            emphasized: true,
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _clearing ? null : _clearCache,
              icon: _clearing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined),
              label: Text(_isArabic ? 'مسح الكاش' : 'Clear cache'),
            ),
            const SizedBox(height: 8),
            Text(
              _isArabic
                  ? 'يتم الاحتفاظ بالوسائط لمدة تصل إلى 30 يوم مع تنظيف تلقائي وحدود حجم.'
                  : 'Media is cached for up to 30 days with auto cleanup and size limits.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CacheRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _CacheRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
      fontSize: emphasized ? 16 : 14,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}
