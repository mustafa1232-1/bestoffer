import 'package:flutter/material.dart';

import '../media/social_safe_image.dart';
import '../pickers/social_media_picker_v3.dart';

/// Post composer mode (§3).
enum PostComposerMode { standard, merchantReview }

/// Merchant-review context. `verifiedPurchase` is NEVER trusted from Flutter —
/// the backend sets it only when [orderId] links to a completed order owned by
/// the user.
class MerchantReviewDraft {
  const MerchantReviewDraft({
    required this.merchantId,
    required this.merchantName,
    this.merchantImageUrl,
    this.productId,
    this.orderId,
  });

  final int merchantId;
  final String merchantName;
  final String? merchantImageUrl;
  final int? productId;
  final int? orderId;
}

/// Data emitted by the post composer on publish.
class PostComposerResult {
  const PostComposerResult({
    required this.caption,
    required this.media,
    required this.audience,
    required this.commentsEnabled,
    this.mode = PostComposerMode.standard,
    this.rating,
    this.review,
  });

  final String caption;
  final List<PickedSocialMedia> media;
  final String audience;
  final bool commentsEnabled;
  final PostComposerMode mode;
  final int? rating;
  final MerchantReviewDraft? review;

  /// 'merchant_review' in review mode, else 'image'/'text'.
  String get postKind {
    if (mode == PostComposerMode.merchantReview) return 'merchant_review';
    return media.isEmpty ? 'text' : 'image';
  }
}

/// Full-screen V3 post composer (§2). Uses native-picker results only (never
/// FilePicker). Supports a media carousel with reordering, caption, audience,
/// and a comments toggle. Publishing is delegated to [onPublish] so the widget
/// stays decoupled from Riverpod and is route-testable.
class PostComposerV3 extends StatefulWidget {
  const PostComposerV3({
    super.key,
    required this.initialMedia,
    this.mode = PostComposerMode.standard,
    this.review,
    this.onPublish,
    this.onAddMore,
  });

  final List<PickedSocialMedia> initialMedia;
  final PostComposerMode mode;
  final MerchantReviewDraft? review;

  /// Returns true on success (composer then pops).
  final Future<bool> Function(PostComposerResult result)? onPublish;

  /// Opens the native picker again to append media.
  final Future<List<PickedSocialMedia>> Function()? onAddMore;

  @override
  State<PostComposerV3> createState() => _PostComposerV3State();
}

class _PostComposerV3State extends State<PostComposerV3> {
  final _caption = TextEditingController();
  late List<PickedSocialMedia> _media;
  String _audience = 'public';
  bool _comments = true;
  bool _publishing = false;
  String? _error;
  int _rating = 0;

  bool get _isReview => widget.mode == PostComposerMode.merchantReview;

  @override
  void initState() {
    super.initState();
    _media = List.of(widget.initialMedia);
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_publishing) return;
    if (_isReview && _rating < 1) {
      setState(() => _error = 'التقييم مطلوب');
      return;
    }
    if (!_isReview && _media.isEmpty && _caption.text.trim().isEmpty) {
      setState(() => _error = 'أضف نصًا أو وسائط');
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
    });
    final ok = await (widget.onPublish?.call(
          PostComposerResult(
            caption: _caption.text.trim(),
            media: _media,
            audience: _audience,
            commentsEnabled: _comments,
            mode: widget.mode,
            rating: _isReview ? _rating : null,
            review: widget.review,
          ),
        ) ??
        Future.value(false));
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _publishing = false;
        _error = 'فشل النشر، حاول مرة أخرى';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isReview ? 'تقييم متجر' : 'منشور جديد'),
        actions: [
          TextButton(
            onPressed: _publishing ? null : _publish,
            child: _publishing
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('نشر'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_isReview && widget.review != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.storefront_rounded)),
              title: Text(
                widget.review!.merchantName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('تقييمك يساعد بقية السكان'),
            ),
            Row(
              children: List.generate(
                5,
                (i) => IconButton(
                  onPressed: () => setState(() => _rating = i + 1),
                  icon: Icon(
                    i < _rating ? Icons.star_rounded : Icons.star_border_rounded,
                    color: Colors.amber,
                  ),
                ),
              ),
            ),
            const Divider(),
          ],
          if (_media.isNotEmpty)
            SizedBox(
              height: 220,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: true,
                itemCount: _media.length,
                onReorder: (oldI, newI) {
                  setState(() {
                    if (newI > oldI) newI -= 1;
                    final m = _media.removeAt(oldI);
                    _media.insert(newI, m);
                  });
                },
                itemBuilder: (context, i) {
                  final m = _media[i];
                  return Padding(
                    key: ValueKey('post-media-${m.path}-$i'),
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 150,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            m.isVideo
                                ? const ColoredBox(
                                    color: Color(0xFF0D1B2A),
                                    child: Icon(Icons.movie_creation_outlined,
                                        color: Colors.white38, size: 36),
                                  )
                                : SocialSafeImage(imageUrl: m.path),
                            Positioned(
                              top: 4, right: 4,
                              child: GestureDetector(
                                onTap: () => setState(() => _media.removeAt(i)),
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (widget.onAddMore != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () async {
                  final more = await widget.onAddMore!.call();
                  if (more.isNotEmpty) setState(() => _media.addAll(more));
                },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('إضافة وسائط'),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _caption,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'اكتب شيئًا…  #وسم  @إشارة',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _comments,
            onChanged: (v) => setState(() => _comments = v),
            title: const Text('السماح بالتعليقات'),
          ),
          ListTile(
            leading: Icon(_audience == 'public' ? Icons.public : Icons.group),
            title: Text(_audience == 'public' ? 'الجميع' : 'المتابعون'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => setState(
              () => _audience = _audience == 'public' ? 'followers' : 'public',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
