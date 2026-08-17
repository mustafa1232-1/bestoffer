import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:social_core/social_api.dart';

/// Giphy-backed GIF picker sheet (Tenor's public API was retired 2026-06-30).
/// Shows trending GIFs on open, live-searches as the user types, and returns the
/// chosen [SocialGif] via `Navigator.pop`. The caller downloads + sends the GIF
/// (usually via [SocialApi.downloadRemoteMedia] + the image-attachment pipeline).
///
/// Lives in `social_ui` so every chat surface — the main app and the embedded
/// `app_user_runtime` — can share one implementation.
///
/// ```dart
/// final gif = await showModalBottomSheet<SocialGif>(
///   context: context,
///   showDragHandle: true,
///   isScrollControlled: true,
///   builder: (_) => SocialGifPickerSheet(api: api, isEnglish: isEnglish),
/// );
/// ```
class SocialGifPickerSheet extends StatefulWidget {
  const SocialGifPickerSheet({
    super.key,
    required this.api,
    required this.isEnglish,
  });

  final SocialApi api;
  final bool isEnglish;

  @override
  State<SocialGifPickerSheet> createState() => _SocialGifPickerSheetState();
}

class _SocialGifPickerSheetState extends State<SocialGifPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _enabled = true;
  String? _error;
  List<SocialGif> _results = const <SocialGif>[];
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _runSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(value),
    );
  }

  Future<void> _runSearch(String query) async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await widget.api.searchGifs(query: query, limit: 30);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _enabled = out.enabled;
        _results = out.results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _error = widget.isEnglish
            ? 'Could not load GIFs. Check your connection.'
            : 'تعذّر تحميل GIF. تحقّق من الاتصال.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnglish = widget.isEnglish;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'GIF',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Powered by GIPHY',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onQueryChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _runSearch,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: isEnglish ? 'Search GIFs' : 'ابحث عن GIF',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              Flexible(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final isEnglish = widget.isEnglish;
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (!_enabled) {
      return _centeredHint(
        context,
        isEnglish
            ? 'GIF search is not configured on the server yet.'
            : 'بحث GIF غير مُفعّل على الخادم بعد.',
      );
    }
    if (_error != null) {
      return _centeredHint(context, _error!);
    }
    if (_results.isEmpty) {
      return _centeredHint(
        context,
        isEnglish ? 'No GIFs found.' : 'لا توجد نتائج GIF.',
      );
    }
    final tileColor =
        Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.4,
            );
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final gif = _results[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(gif),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: gif.previewUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              placeholder: (context, _) => Container(color: tileColor),
              errorWidget: (context, _, __) => Container(
                color: tileColor,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _centeredHint(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
