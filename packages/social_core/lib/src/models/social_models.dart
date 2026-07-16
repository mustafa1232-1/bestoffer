import '../core/parsers.dart';

List<String> _parseBadgeKeys(dynamic raw) {
  final source = List<dynamic>.from(raw as List? ?? const []);
  return source
      .map((entry) {
        if (entry is Map) {
          final key = parseString(entry['key']);
          if (key.isNotEmpty) return key;
          return parseString(entry['label']);
        }
        return parseString(entry);
      })
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

String? _parseLocalContextLabel(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map) {
    final label = parseNullableString(raw['label']);
    if (label != null && label.isNotEmpty) return label;
    final type = parseString(raw['type']);
    final code = parseNullableString(raw['code']);
    switch (type) {
      case 'same_building':
        return code == null || code.isEmpty
            ? 'نفس البناية'
            : 'نفس البناية • $code';
      case 'same_compound':
        return code == null || code.isEmpty
            ? 'نفس المجمع'
            : 'نفس المجمع • $code';
      case 'same_block':
        return code == null || code.isEmpty
            ? 'نفس البلوك'
            : 'نفس البلوك • $code';
      default:
        return null;
    }
  }
  return parseNullableString(raw);
}

class SocialAuthor {
  final int id;
  final String? username;
  final String fullName;
  final String? imageUrl;
  final String? phone;
  final String role;
  final List<String> badges;
  final bool isResidentVerified;
  final bool isMerchantVerified;
  final bool isPremiumCreator;

  const SocialAuthor({
    required this.id,
    this.username,
    required this.fullName,
    required this.imageUrl,
    required this.phone,
    required this.role,
    this.badges = const <String>[],
    this.isResidentVerified = false,
    this.isMerchantVerified = false,
    this.isPremiumCreator = false,
  });

  factory SocialAuthor.fromJson(Map<String, dynamic> j) => SocialAuthor(
    id: parseInt(j['id']),
    username: parseNullableString(j['username']),
    fullName: parseString(j['fullName'] ?? j['full_name']),
    imageUrl: parseNullableString(j['imageUrl'] ?? j['image_url']),
    phone: parseNullableString(j['phone']),
    role: parseString(j['role'], fallback: 'user'),
    badges: _parseBadgeKeys(j['badges']),
    isResidentVerified: parseBool(
      j['isResidentVerified'] ?? j['is_resident_verified'],
    ),
    isMerchantVerified: parseBool(
      j['isMerchantVerified'] ?? j['is_merchant_verified'],
    ),
    isPremiumCreator: parseBool(
      j['isPremiumCreator'] ?? j['is_premium_creator'],
    ),
  );

  bool get hasIdentityData =>
      id > 0 ||
      (username ?? '').trim().isNotEmpty ||
      fullName.trim().isNotEmpty ||
      (imageUrl ?? '').trim().isNotEmpty ||
      (phone ?? '').trim().isNotEmpty;

  SocialAuthor copyWith({
    int? id,
    String? username,
    String? fullName,
    String? imageUrl,
    String? phone,
    String? role,
    List<String>? badges,
    bool? isResidentVerified,
    bool? isMerchantVerified,
    bool? isPremiumCreator,
    bool clearUsername = false,
    bool clearImageUrl = false,
    bool clearPhone = false,
  }) {
    return SocialAuthor(
      id: id ?? this.id,
      username: clearUsername ? null : (username ?? this.username),
      fullName: fullName ?? this.fullName,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      phone: clearPhone ? null : (phone ?? this.phone),
      role: role ?? this.role,
      badges: badges ?? this.badges,
      isResidentVerified: isResidentVerified ?? this.isResidentVerified,
      isMerchantVerified: isMerchantVerified ?? this.isMerchantVerified,
      isPremiumCreator: isPremiumCreator ?? this.isPremiumCreator,
    );
  }

  SocialAuthor mergedWith(SocialAuthor? fallback) {
    if (fallback == null) return this;
    final normalizedUsername = (username ?? '').trim();
    final normalizedImage = (imageUrl ?? '').trim();
    final normalizedPhone = (phone ?? '').trim();
    final normalizedRole = role.trim();
    return SocialAuthor(
      id: id > 0 ? id : fallback.id,
      username: normalizedUsername.isNotEmpty
          ? normalizedUsername
          : fallback.username,
      fullName: fullName.trim().isNotEmpty ? fullName : fallback.fullName,
      imageUrl: normalizedImage.isNotEmpty
          ? normalizedImage
          : fallback.imageUrl,
      phone: normalizedPhone.isNotEmpty ? normalizedPhone : fallback.phone,
      role: normalizedRole.isNotEmpty ? normalizedRole : fallback.role,
      badges: <String>{
        ...fallback.badges,
        ...badges,
      }.where((entry) => entry.trim().isNotEmpty).toList(growable: false),
      isResidentVerified: isResidentVerified || fallback.isResidentVerified,
      isMerchantVerified: isMerchantVerified || fallback.isMerchantVerified,
      isPremiumCreator: isPremiumCreator || fallback.isPremiumCreator,
    );
  }
}

class SocialMediaAsset {
  final int? id;
  final String? provider;
  final String? streamUid;
  final String? normalizedUrl;
  final String? posterUrl;
  final String? playbackUrl;
  final String? thumbnailUrl;
  final double? aspectRatio;
  final int? durationMs;
  final String? failureCode;
  final String? processingStatus;
  final DateTime? createdAt;

  const SocialMediaAsset({
    required this.id,
    required this.provider,
    required this.streamUid,
    required this.normalizedUrl,
    required this.posterUrl,
    required this.playbackUrl,
    required this.thumbnailUrl,
    required this.aspectRatio,
    required this.durationMs,
    required this.failureCode,
    required this.processingStatus,
    required this.createdAt,
  });

  factory SocialMediaAsset.fromJson(Map<String, dynamic> j) => SocialMediaAsset(
    id: parseNullableInt(j['id']),
    provider: parseNullableString(j['provider'] ?? j['provider_type']),
    streamUid: parseNullableString(j['streamUid'] ?? j['stream_uid']),
    normalizedUrl: parseNullableString(
      j['normalizedUrl'] ?? j['normalized_url'],
    ),
    posterUrl: parseNullableString(j['posterUrl'] ?? j['poster_url']),
    playbackUrl: parseNullableString(j['playbackUrl'] ?? j['playback_url']),
    thumbnailUrl: parseNullableString(j['thumbnailUrl'] ?? j['thumbnail_url']),
    aspectRatio: j['aspectRatio'] == null
        ? null
        : parseDouble(j['aspectRatio'], fallback: 0),
    durationMs: parseNullableInt(j['durationMs'] ?? j['duration_ms']),
    failureCode: parseNullableString(j['failureCode'] ?? j['failure_code']),
    processingStatus: parseNullableString(
      j['processingStatus'] ?? j['processing_status'],
    ),
    createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
  );

  bool get isReady => (processingStatus ?? '').trim().toLowerCase() == 'ready';
}

class SocialMediaUploadSession {
  final int assetId;
  final String streamUid;
  final String uploadUrl;
  final String sourceType;
  final String mediaKind;
  final String processingStatus;
  final bool readyToStream;
  final SocialMediaAsset? asset;

  const SocialMediaUploadSession({
    required this.assetId,
    required this.streamUid,
    required this.uploadUrl,
    required this.sourceType,
    required this.mediaKind,
    required this.processingStatus,
    required this.readyToStream,
    required this.asset,
  });

  factory SocialMediaUploadSession.fromJson(Map<String, dynamic> j) {
    final nestedAsset = j['asset'] is Map
        ? SocialMediaAsset.fromJson(
            Map<String, dynamic>.from(j['asset'] as Map),
          )
        : null;
    return SocialMediaUploadSession(
      assetId: parseInt(j['assetId'] ?? j['asset_id']),
      streamUid: parseString(j['streamUid'] ?? j['stream_uid']),
      uploadUrl: parseString(j['uploadUrl'] ?? j['upload_url']),
      sourceType: parseString(
        j['sourceType'] ?? j['source_type'],
        fallback: 'reel',
      ),
      mediaKind: parseString(
        j['mediaKind'] ?? j['media_kind'],
        fallback: 'video',
      ),
      processingStatus: parseString(
        j['processingStatus'] ?? j['processing_status'],
        fallback: 'pending',
      ),
      readyToStream: parseBool(j['readyToStream'] ?? j['ready_to_stream']),
      asset: nestedAsset,
    );
  }
}

class SocialPostMediaItem {
  final int id;
  final int sortOrder;
  final String? mediaUrl;
  final String? mediaKind;
  final SocialMediaAsset? asset;

  const SocialPostMediaItem({
    required this.id,
    required this.sortOrder,
    required this.mediaUrl,
    required this.mediaKind,
    required this.asset,
  });

  factory SocialPostMediaItem.fromJson(Map<String, dynamic> j) =>
      SocialPostMediaItem(
        id: parseInt(j['id']),
        sortOrder: parseInt(j['sortOrder'] ?? j['sort_order'] ?? 0),
        mediaUrl: parseNullableString(j['mediaUrl'] ?? j['media_url']),
        mediaKind: parseNullableString(j['mediaKind'] ?? j['media_kind']),
        asset: j['asset'] is Map
            ? SocialMediaAsset.fromJson(
                Map<String, dynamic>.from(j['asset'] as Map),
              )
            : null,
      );
}

class SocialContentLink {
  final String targetType;
  final int? merchantId;
  final int? productId;
  final int? offerId;
  final int? couponId;

  const SocialContentLink({
    required this.targetType,
    required this.merchantId,
    required this.productId,
    required this.offerId,
    required this.couponId,
  });

  factory SocialContentLink.fromJson(Map<String, dynamic> j) =>
      SocialContentLink(
        targetType: parseString(
          j['targetType'] ?? j['target_type'],
          fallback: 'merchant',
        ),
        merchantId: parseNullableInt(j['merchantId'] ?? j['merchant_id']),
        productId: parseNullableInt(j['productId'] ?? j['product_id']),
        offerId: parseNullableInt(j['offerId'] ?? j['offer_id']),
        couponId: parseNullableInt(j['couponId'] ?? j['coupon_id']),
      );
}

class SocialPost {
  final int id;
  final int userId;
  final String postKind;
  final String audienceScopeType;
  final String? audienceScopeCode;
  final String caption;
  final SocialSharedEntity? sharedEntity;
  final String? mediaUrl;
  final String? mediaKind;
  final int? merchantId;
  final String? merchantName;
  final String? merchantType;
  final String? merchantImageUrl;
  final int? reviewRating;
  final int likesCount;
  final int commentsCount;
  final int savesCount;
  final int impressionsCount;
  final int reelViewsCount;
  final bool isLiked;
  final bool isSaved;
  final double? rankingScore;
  final int reportCount;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final SocialMediaAsset? asset;
  final List<SocialPostMediaItem> mediaGallery;
  final SocialContentLink? contentLink;
  final SocialAuthor author;

  const SocialPost({
    required this.id,
    required this.userId,
    required this.postKind,
    required this.audienceScopeType,
    required this.audienceScopeCode,
    required this.caption,
    required this.sharedEntity,
    required this.mediaUrl,
    required this.mediaKind,
    required this.merchantId,
    required this.merchantName,
    required this.merchantType,
    required this.merchantImageUrl,
    required this.reviewRating,
    required this.likesCount,
    required this.commentsCount,
    required this.savesCount,
    required this.impressionsCount,
    required this.reelViewsCount,
    required this.isLiked,
    required this.isSaved,
    required this.rankingScore,
    required this.reportCount,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.asset,
    required this.mediaGallery,
    required this.contentLink,
    required this.author,
  });

  factory SocialPost.fromJson(Map<String, dynamic> j) => SocialPost(
    id: parseInt(j['id']),
    userId: parseInt(j['userId'] ?? j['user_id']),
    postKind: parseString(j['postKind'] ?? j['post_kind'], fallback: 'text'),
    audienceScopeType: parseString(
      j['audienceScopeType'] ?? j['audience_scope_type'],
      fallback: 'global',
    ).toLowerCase(),
    audienceScopeCode: parseNullableString(
      j['audienceScopeCode'] ?? j['audience_scope_code'],
    ),
    caption: parseString(j['caption']),
    sharedEntity:
        j['sharedEntity'] is Map ||
            j['shared_entity'] is Map ||
            j['sharedEntityType'] != null ||
            j['shared_entity_type'] != null
        ? SocialSharedEntity.fromJson(
            Map<String, dynamic>.from(
              (j['sharedEntity'] ?? j['shared_entity']) as Map? ??
                  <String, dynamic>{
                    'type':
                        j['sharedEntityType'] ??
                        j['shared_entity_type'] ??
                        'post',
                    'id': j['sharedEntityId'] ?? j['shared_entity_id'],
                    'snapshot':
                        j['sharedSnapshot'] ??
                        j['shared_snapshot'] ??
                        j['sharedSnapshotJson'] ??
                        j['shared_snapshot_json'],
                  },
            ),
          )
        : null,
    mediaUrl: parseNullableString(j['mediaUrl'] ?? j['media_url']),
    mediaKind: parseNullableString(j['mediaKind'] ?? j['media_kind']),
    merchantId: j['merchantId'] == null && j['merchant_id'] == null
        ? null
        : parseInt(j['merchantId'] ?? j['merchant_id']),
    merchantName: parseNullableString(j['merchantName'] ?? j['merchant_name']),
    merchantType: parseNullableString(j['merchantType'] ?? j['merchant_type']),
    merchantImageUrl: parseNullableString(
      j['merchantImageUrl'] ?? j['merchant_image_url'],
    ),
    reviewRating: j['reviewRating'] == null && j['review_rating'] == null
        ? null
        : parseInt(j['reviewRating'] ?? j['review_rating']),
    likesCount: parseInt(j['likesCount'] ?? j['likes_count']),
    commentsCount: parseInt(j['commentsCount'] ?? j['comments_count']),
    savesCount: parseInt(j['savesCount'] ?? j['saves_count']),
    impressionsCount: parseInt(j['impressionsCount'] ?? j['impressions_count']),
    reelViewsCount: parseInt(j['reelViewsCount'] ?? j['reel_views_count']),
    isLiked: parseBool(j['isLiked'] ?? j['is_liked']),
    isSaved: parseBool(j['isSaved'] ?? j['is_saved']),
    rankingScore: (j['rankingScore'] ?? j['ranking_score']) == null
        ? null
        : double.tryParse('${j['rankingScore'] ?? j['ranking_score']}'),
    reportCount: parseInt(j['reportCount'] ?? j['report_count']),
    archivedAt: parseNullableDateTime(j['archivedAt'] ?? j['archived_at']),
    createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
    updatedAt: parseNullableDateTime(j['updatedAt'] ?? j['updated_at']),
    asset: j['asset'] is Map
        ? SocialMediaAsset.fromJson(
            Map<String, dynamic>.from(j['asset'] as Map),
          )
        : null,
    mediaGallery:
        List<dynamic>.from(j['mediaGallery'] ?? j['media_gallery'] ?? const [])
            .whereType<Map>()
            .map(
              (e) => SocialPostMediaItem.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(growable: false),
    contentLink: j['contentLink'] is Map || j['content_link'] is Map
        ? SocialContentLink.fromJson(
            Map<String, dynamic>.from(
              (j['contentLink'] ?? j['content_link']) as Map,
            ),
          )
        : null,
    author: SocialAuthor.fromJson(
      Map<String, dynamic>.from(j['author'] as Map? ?? const {}),
    ),
  );

  SocialPost copyWith({
    int? likesCount,
    int? commentsCount,
    int? savesCount,
    bool? isLiked,
    bool? isSaved,
    DateTime? createdAt,
    SocialAuthor? author,
    SocialSharedEntity? sharedEntity,
    bool clearSharedEntity = false,
  }) {
    return SocialPost(
      id: id,
      userId: userId,
      postKind: postKind,
      audienceScopeType: audienceScopeType,
      audienceScopeCode: audienceScopeCode,
      caption: caption,
      sharedEntity: clearSharedEntity
          ? null
          : (sharedEntity ?? this.sharedEntity),
      mediaUrl: mediaUrl,
      mediaKind: mediaKind,
      merchantId: merchantId,
      merchantName: merchantName,
      merchantType: merchantType,
      merchantImageUrl: merchantImageUrl,
      reviewRating: reviewRating,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      savesCount: savesCount ?? this.savesCount,
      impressionsCount: impressionsCount,
      reelViewsCount: reelViewsCount,
      isLiked: isLiked ?? this.isLiked,
      isSaved: isSaved ?? this.isSaved,
      rankingScore: rankingScore,
      reportCount: reportCount,
      archivedAt: archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt,
      asset: asset,
      mediaGallery: mediaGallery,
      contentLink: contentLink,
      author: author ?? this.author,
    );
  }
}

String normalizeSocialPostMediaClass(SocialPost post) {
  final postKind = post.postKind.trim().toLowerCase();
  final mediaKind = (post.mediaKind ?? '').trim().toLowerCase();
  final sharedKind = post.sharedEntity?.type.trim().toLowerCase() ?? '';
  final candidates = <String>[
    if (mediaKind.isNotEmpty) mediaKind,
    if (sharedKind.isNotEmpty) sharedKind,
    if (postKind.isNotEmpty) postKind,
  ];
  for (final candidate in candidates) {
    switch (candidate) {
      case 'reel':
        return 'reel';
      case 'video':
        return 'video';
      case 'image':
      case 'photo':
        return 'image';
      case 'merchant_review':
      case 'review':
        return 'merchant_review';
    }
  }
  return 'text';
}

bool isSocialMerchantReviewPost(SocialPost post) =>
    normalizeSocialPostMediaClass(post) == 'merchant_review';

bool isSocialReelPost(SocialPost post) =>
    normalizeSocialPostMediaClass(post) == 'reel';

bool isSocialVideoPost(SocialPost post) {
  final kind = normalizeSocialPostMediaClass(post);
  return kind == 'reel' || kind == 'video';
}

bool isSocialSharedReelPost(SocialPost post) =>
    (post.sharedEntity?.type.trim().toLowerCase() ?? '') == 'reel';

bool isSocialImagePost(SocialPost post) =>
    normalizeSocialPostMediaClass(post) == 'image';

/// True when [url] is a streaming manifest or a raw video file — such URLs must
/// NEVER be used as a poster/image (doing so is exactly what produced the broken
/// image placeholder for reels in the community feed).
bool socialUrlIsVideoOrManifest(String? url) {
  final value = (url ?? '').trim().toLowerCase();
  if (value.isEmpty) return false;
  final path = value.split('?').first;
  return path.endsWith('.m3u8') ||
      path.endsWith('.mpd') ||
      path.endsWith('.ts') ||
      value.contains('format=hls') ||
      value.contains('/manifest/') ||
      path.endsWith('.mp4') ||
      path.endsWith('.mov') ||
      path.endsWith('.m4v') ||
      path.endsWith('.webm') ||
      path.endsWith('.mkv');
}

/// A Cloudflare Stream reel can synthesize a still thumbnail from its stream UID.
/// This is a provider-generated *image*, safe for the poster slot — the missing
/// piece that left reels with no feed thumbnail.
String? socialCloudflareThumbnail(SocialMediaAsset? asset) {
  final uid = (asset?.streamUid ?? '').trim();
  if (uid.isEmpty) return null;
  final prov = (asset?.provider ?? '').trim().toLowerCase();
  if (prov.contains('cloudflare') || prov.contains('stream') || prov.isEmpty) {
    return 'https://videodelivery.net/$uid/thumbnails/thumbnail.jpg';
  }
  return null;
}

/// Resolves an IMAGE-ONLY poster for a post. Returns the first candidate that is
/// a real image; a playback/HLS/MP4 URL is never returned (that mistake rendered
/// reels as a broken-image placeholder). For Cloudflare reels with no explicit
/// thumbnail, it synthesizes the provider thumbnail from the stream UID.
String? resolveSocialPostPosterUrl(
  SocialPost post, {
  bool preferMerchantFallback = true,
}) {
  final galleryFirst = post.mediaGallery.isNotEmpty
      ? post.mediaGallery.first
      : null;
  final galleryAsset = galleryFirst?.asset;
  final asset = post.asset;
  final shared = post.sharedEntity;
  final sharedSnapshot = shared?.snapshot ?? const <String, dynamic>{};

  final candidates = <String?>[
    if (shared?.type.trim().toLowerCase() == 'reel') ...[
      parseNullableString(sharedSnapshot['posterUrl']),
      parseNullableString(sharedSnapshot['poster_url']),
      parseNullableString(sharedSnapshot['thumbnailUrl']),
      parseNullableString(sharedSnapshot['thumbnail_url']),
      parseNullableString(sharedSnapshot['playbackUrl']),
      parseNullableString(sharedSnapshot['playback_url']),
    ],
    galleryAsset?.thumbnailUrl,
    galleryAsset?.posterUrl,
    socialCloudflareThumbnail(galleryAsset),
    asset?.thumbnailUrl,
    asset?.posterUrl,
    socialCloudflareThumbnail(asset),
  ];

  for (final candidate in candidates) {
    final value = (candidate ?? '').trim();
    if (value.isEmpty) continue;
    if (socialUrlIsVideoOrManifest(value)) continue; // image slot only
    return value;
  }

  // Non-video posts may legitimately use their direct media url as the image.
  if (!isSocialVideoPost(post)) {
    for (final candidate in <String?>[
      galleryAsset?.normalizedUrl,
      galleryFirst?.mediaUrl,
      asset?.normalizedUrl,
      post.mediaUrl,
    ]) {
      final value = (candidate ?? '').trim();
      if (value.isEmpty || socialUrlIsVideoOrManifest(value)) continue;
      return value;
    }
  }

  if (preferMerchantFallback && isSocialMerchantReviewPost(post)) {
    final merchantImage = (post.merchantImageUrl ?? '').trim();
    if (merchantImage.isNotEmpty) return merchantImage;
  }
  return null;
}

String? resolveSocialPostVideoUrl(SocialPost post) {
  final galleryFirst = post.mediaGallery.isNotEmpty
      ? post.mediaGallery.first
      : null;
  final shared = post.sharedEntity;
  final sharedSnapshot = shared?.snapshot ?? const <String, dynamic>{};
  final sharedVideo = shared?.type.trim().toLowerCase() == 'reel'
      ? parseNullableString(
          sharedSnapshot['playbackUrl'] ??
              sharedSnapshot['playback_url'] ??
              sharedSnapshot['videoUrl'] ??
              sharedSnapshot['video_url'],
        )
      : null;
  if ((sharedVideo ?? '').trim().isNotEmpty) return sharedVideo!.trim();
  final galleryUrl =
      (galleryFirst?.asset?.playbackUrl ??
              galleryFirst?.asset?.normalizedUrl ??
              galleryFirst?.mediaUrl ??
              '')
          .trim();
  if (galleryUrl.isNotEmpty) return galleryUrl;
  if (!isSocialVideoPost(post)) return null;
  final assetUrl = (post.asset?.playbackUrl ?? post.asset?.normalizedUrl ?? '')
      .trim();
  if (assetUrl.isNotEmpty) return assetUrl;
  final mediaUrl = (post.mediaUrl ?? '').trim();
  if (mediaUrl.isNotEmpty) return mediaUrl;
  return null;
}

class SocialComment {
  final int id;
  final int postId;
  final int userId;
  final String body;
  final int? parentCommentId;
  final int likesCount;
  final bool isLiked;
  final bool isDeleted;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final SocialAuthor author;

  const SocialComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.body,
    required this.parentCommentId,
    required this.likesCount,
    required this.isLiked,
    required this.isDeleted,
    required this.createdAt,
    required this.editedAt,
    required this.author,
  });

  factory SocialComment.fromJson(Map<String, dynamic> j) => SocialComment(
    id: parseInt(j['id']),
    postId: parseInt(j['postId'] ?? j['post_id']),
    userId: parseInt(j['userId'] ?? j['user_id']),
    body: parseString(j['body']),
    parentCommentId: parseNullableInt(
      j['parentCommentId'] ?? j['parent_comment_id'],
    ),
    likesCount: parseInt(j['likesCount'] ?? j['likes_count']),
    isLiked: parseBool(j['isLiked'] ?? j['is_liked']),
    isDeleted: parseBool(j['isDeleted'] ?? j['is_deleted']),
    createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
    editedAt: parseNullableDateTime(j['editedAt'] ?? j['edited_at']),
    author: SocialAuthor.fromJson(
      Map<String, dynamic>.from(j['author'] as Map? ?? const {}),
    ),
  );
}

class SocialMerchantOption {
  final int id;
  final String name;
  final String type;
  final String activityType;
  final String phone;
  final String? imageUrl;
  final bool canReview;
  final int eligibleOrdersCount;
  final String? eligibilityLabel;
  final String? eligibilityReason;

  const SocialMerchantOption({
    required this.id,
    required this.name,
    required this.type,
    this.activityType = 'market',
    required this.phone,
    required this.imageUrl,
    this.canReview = false,
    this.eligibleOrdersCount = 0,
    this.eligibilityLabel,
    this.eligibilityReason,
  });

  factory SocialMerchantOption.fromJson(Map<String, dynamic> j) =>
      SocialMerchantOption(
        id: parseInt(j['id']),
        name: parseString(j['name']),
        type: parseString(j['type'], fallback: 'market'),
        activityType: parseString(
          j['activityType'] ?? j['activity_type'],
          fallback: parseString(j['type'], fallback: 'market'),
        ),
        phone: parseString(j['phone']),
        imageUrl: parseNullableString(j['imageUrl'] ?? j['image_url']),
        canReview: parseBool(j['canReview'] ?? j['can_review']),
        eligibleOrdersCount: parseInt(
          j['eligibleOrdersCount'] ?? j['eligible_orders_count'],
        ),
        eligibilityLabel: parseNullableString(
          j['eligibilityLabel'] ?? j['eligibility_label'],
        ),
        eligibilityReason: parseNullableString(
          j['eligibilityReason'] ?? j['eligibility_reason'],
        ),
      );
}

class SocialStory {
  final int id;
  final int userId;
  final String caption;
  final String? mediaUrl;
  final String? mediaKind;
  final SocialMediaAsset? asset;
  final SocialStoryStyle style;
  final bool allowLikes;
  final bool allowPrivateReplies;
  final bool allowComments;
  final bool allowSharing;
  final bool allowReshare;
  final bool isViewed;
  final bool isMine;
  final int likesCount;
  final int commentsCount;
  final bool isLiked;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const SocialStory({
    required this.id,
    required this.userId,
    required this.caption,
    required this.mediaUrl,
    required this.mediaKind,
    required this.asset,
    required this.style,
    this.allowLikes = true,
    this.allowPrivateReplies = true,
    this.allowComments = true,
    this.allowSharing = true,
    this.allowReshare = true,
    required this.isViewed,
    required this.isMine,
    required this.likesCount,
    required this.commentsCount,
    required this.isLiked,
    required this.archivedAt,
    required this.createdAt,
    required this.expiresAt,
  });

  factory SocialStory.fromJson(Map<String, dynamic> j) => SocialStory(
    id: parseInt(j['id']),
    userId: parseInt(j['userId'] ?? j['user_id']),
    caption: parseString(j['caption']),
    mediaUrl: parseNullableString(j['mediaUrl'] ?? j['media_url']),
    mediaKind: parseNullableString(j['mediaKind'] ?? j['media_kind']),
    allowLikes: parseBool(
      j['allowLikes'] ??
          j['allow_likes'] ??
          (j['storyInteractionSettings'] is Map
              ? (j['storyInteractionSettings'] as Map)['allowLikes'] ??
                    (j['storyInteractionSettings'] as Map)['allow_likes']
              : null) ??
          (j['story_interaction_settings'] is Map
              ? (j['story_interaction_settings'] as Map)['allowLikes'] ??
                    (j['story_interaction_settings'] as Map)['allow_likes']
              : null),
      fallback: true,
    ),
    allowPrivateReplies: parseBool(
      j['allowPrivateReplies'] ??
          j['allow_private_replies'] ??
          (j['storyInteractionSettings'] is Map
              ? (j['storyInteractionSettings'] as Map)['allowPrivateReplies'] ??
                    (j['storyInteractionSettings']
                        as Map)['allow_private_replies']
              : null) ??
          (j['story_interaction_settings'] is Map
              ? (j['story_interaction_settings']
                        as Map)['allowPrivateReplies'] ??
                    (j['story_interaction_settings']
                        as Map)['allow_private_replies']
              : null),
      fallback: true,
    ),
    allowComments: parseBool(
      j['allowComments'] ??
          j['allow_comments'] ??
          (j['storyInteractionSettings'] is Map
              ? (j['storyInteractionSettings'] as Map)['allowComments'] ??
                    (j['storyInteractionSettings'] as Map)['allow_comments']
              : null) ??
          (j['story_interaction_settings'] is Map
              ? (j['story_interaction_settings'] as Map)['allowComments'] ??
                    (j['story_interaction_settings'] as Map)['allow_comments']
              : null),
      fallback: true,
    ),
    allowSharing: parseBool(
      j['allowSharing'] ??
          j['allow_sharing'] ??
          (j['storyInteractionSettings'] is Map
              ? (j['storyInteractionSettings'] as Map)['allowSharing'] ??
                    (j['storyInteractionSettings'] as Map)['allow_sharing']
              : null) ??
          (j['story_interaction_settings'] is Map
              ? (j['story_interaction_settings'] as Map)['allowSharing'] ??
                    (j['story_interaction_settings'] as Map)['allow_sharing']
              : null),
      fallback: true,
    ),
    allowReshare: parseBool(
      j['allowReshare'] ??
          j['allow_reshare'] ??
          (j['storyInteractionSettings'] is Map
              ? (j['storyInteractionSettings'] as Map)['allowReshare'] ??
                    (j['storyInteractionSettings'] as Map)['allow_reshare']
              : null) ??
          (j['story_interaction_settings'] is Map
              ? (j['story_interaction_settings'] as Map)['allowReshare'] ??
                    (j['story_interaction_settings'] as Map)['allow_reshare']
              : null),
      fallback: true,
    ),
    asset: j['asset'] is Map
        ? SocialMediaAsset.fromJson(
            Map<String, dynamic>.from(j['asset'] as Map),
          )
        : null,
    style: SocialStoryStyle.fromJson(
      Map<String, dynamic>.from(
        j['storyStyle'] ?? j['story_style'] ?? const <String, dynamic>{},
      ),
    ),
    isViewed: parseBool(j['isViewed'] ?? j['is_viewed']),
    isMine: parseBool(j['isMine'] ?? j['is_mine']),
    likesCount: parseInt(j['likesCount'] ?? j['likes_count']),
    commentsCount: parseInt(j['commentsCount'] ?? j['comments_count']),
    isLiked: parseBool(j['isLiked'] ?? j['is_liked']),
    archivedAt: parseNullableDateTime(j['archivedAt'] ?? j['archived_at']),
    createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
    expiresAt: parseNullableDateTime(j['expiresAt'] ?? j['expires_at']),
  );
}

class SocialStoryStyle {
  final String backgroundColor;
  final String textColor;
  final String textAlign;
  final String fontFamily;
  final String fontWeight;
  final double fontScale;
  final double? clipStartSec;
  final double? clipDurationSec;
  final int? sharedPostId;
  final String? sharedPostAuthor;
  final String? sharedPostMediaUrl;
  final String? sharedPostCaption;
  final String? sharedPostMediaKind;
  final Map<String, dynamic> rawDocument;

  const SocialStoryStyle({
    required this.backgroundColor,
    required this.textColor,
    required this.textAlign,
    required this.fontFamily,
    required this.fontWeight,
    required this.fontScale,
    required this.clipStartSec,
    required this.clipDurationSec,
    required this.sharedPostId,
    required this.sharedPostAuthor,
    required this.sharedPostMediaUrl,
    required this.sharedPostCaption,
    required this.sharedPostMediaKind,
    required this.rawDocument,
  });

  factory SocialStoryStyle.fromJson(Map<String, dynamic> j) => SocialStoryStyle(
    backgroundColor: parseString(
      j['backgroundColor'] ?? j['background_color'],
      fallback: '#1E3A8A',
    ),
    textColor: parseString(
      j['textColor'] ?? j['text_color'],
      fallback: '#FFFFFF',
    ),
    textAlign: parseString(
      j['textAlign'] ?? j['text_align'],
      fallback: 'center',
    ),
    fontFamily: parseString(
      j['fontFamily'] ?? j['font_family'],
      fallback: 'system',
    ),
    fontWeight: parseString(
      j['fontWeight'] ?? j['font_weight'],
      fallback: 'bold',
    ),
    fontScale:
        double.tryParse('${j['fontScale'] ?? j['font_scale'] ?? 1.0}') ?? 1.0,
    clipStartSec: double.tryParse(
      '${j['clipStartSec'] ?? j['clip_start_sec'] ?? ''}',
    ),
    clipDurationSec: double.tryParse(
      '${j['clipDurationSec'] ?? j['clip_duration_sec'] ?? ''}',
    ),
    sharedPostId: parseNullableInt(j['sharedPostId'] ?? j['shared_post_id']),
    sharedPostAuthor: parseNullableString(
      j['sharedPostAuthor'] ?? j['shared_post_author'],
    ),
    sharedPostMediaUrl: parseNullableString(
      j['sharedPostMediaUrl'] ?? j['shared_post_media_url'],
    ),
    sharedPostCaption: parseNullableString(
      j['sharedPostCaption'] ?? j['shared_post_caption'],
    ),
    sharedPostMediaKind: parseNullableString(
      j['sharedPostMediaKind'] ?? j['shared_post_media_kind'],
    ),
    rawDocument: Map<String, dynamic>.from(j),
  );

  Map<String, dynamic> toJson() => {
    'backgroundColor': backgroundColor,
    'textColor': textColor,
    'textAlign': textAlign,
    'fontFamily': fontFamily,
    'fontWeight': fontWeight,
    'fontScale': fontScale,
    if (clipStartSec != null) 'clipStartSec': clipStartSec,
    if (clipDurationSec != null) 'clipDurationSec': clipDurationSec,
    if (sharedPostId != null) 'sharedPostId': sharedPostId,
    if (sharedPostAuthor != null) 'sharedPostAuthor': sharedPostAuthor,
    if (sharedPostMediaUrl != null) 'sharedPostMediaUrl': sharedPostMediaUrl,
    if (sharedPostCaption != null) 'sharedPostCaption': sharedPostCaption,
    if (sharedPostMediaKind != null) 'sharedPostMediaKind': sharedPostMediaKind,
  };
}

class SocialStoryGroup {
  final int userId;
  final SocialAuthor author;
  final DateTime? latestAt;
  final bool hasUnviewed;
  final List<SocialStory> stories;

  const SocialStoryGroup({
    required this.userId,
    required this.author,
    required this.latestAt,
    required this.hasUnviewed,
    required this.stories,
  });

  factory SocialStoryGroup.fromJson(Map<String, dynamic> j) => SocialStoryGroup(
    userId: parseInt(j['userId'] ?? j['user_id']),
    author: SocialAuthor.fromJson(
      Map<String, dynamic>.from(j['author'] as Map? ?? const {}),
    ),
    latestAt: parseNullableDateTime(j['latestAt'] ?? j['latest_at']),
    hasUnviewed: parseBool(j['hasUnviewed'] ?? j['has_unviewed']),
    stories: List<dynamic>.from(j['stories'] as List? ?? const [])
        .map((e) => SocialStory.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false),
  );
}

class SocialUserPostStats {
  final int totalPosts;
  final int imagePosts;
  final int videoPosts;
  final int reviewPosts;
  final int likesReceived;
  final int likesGiven;
  final int commentsReceived;
  final int commentsMade;
  final int activeStories;
  final int highlightsCount;
  final int connectionsCount;
  final int friendsCount;
  final int followersCount;
  final int followingCount;
  final int pendingIncomingCount;
  final int pendingOutgoingCount;

  const SocialUserPostStats({
    required this.totalPosts,
    required this.imagePosts,
    required this.videoPosts,
    required this.reviewPosts,
    required this.likesReceived,
    required this.likesGiven,
    required this.commentsReceived,
    required this.commentsMade,
    required this.activeStories,
    required this.highlightsCount,
    required this.connectionsCount,
    required this.friendsCount,
    required this.followersCount,
    required this.followingCount,
    required this.pendingIncomingCount,
    required this.pendingOutgoingCount,
  });

  factory SocialUserPostStats.fromJson(
    Map<String, dynamic> j,
  ) => SocialUserPostStats(
    totalPosts: parseInt(j['totalPosts'] ?? j['total_posts']),
    imagePosts: parseInt(j['imagePosts'] ?? j['image_posts']),
    videoPosts: parseInt(j['videoPosts'] ?? j['video_posts']),
    reviewPosts: parseInt(j['reviewPosts'] ?? j['review_posts']),
    likesReceived: parseInt(j['likesReceived'] ?? j['likes_received']),
    likesGiven: parseInt(j['likesGiven'] ?? j['likes_given']),
    commentsReceived: parseInt(j['commentsReceived'] ?? j['comments_received']),
    commentsMade: parseInt(j['commentsMade'] ?? j['comments_made']),
    activeStories: parseInt(j['activeStories'] ?? j['active_stories']),
    highlightsCount: parseInt(j['highlightsCount'] ?? j['highlights_count']),
    connectionsCount: parseInt(j['connectionsCount'] ?? j['connections_count']),
    friendsCount: parseInt(
      j['friendsCount'] ?? j['friends_count'] ?? j['connectionsCount'],
    ),
    followersCount: parseInt(j['followersCount'] ?? j['followers_count']),
    followingCount: parseInt(j['followingCount'] ?? j['following_count']),
    pendingIncomingCount: parseInt(
      j['pendingIncomingCount'] ?? j['pending_incoming_count'],
    ),
    pendingOutgoingCount: parseInt(
      j['pendingOutgoingCount'] ?? j['pending_outgoing_count'],
    ),
  );
}

class SocialRelation {
  final String state;
  final String? rawStatus;
  final String? requestDirection;
  final bool canChat;
  final bool canCall;
  final bool canSendRequest;
  final bool blockedByMe;
  final bool blockedByOther;
  final int? otherUserId;
  final int? initiatorUserId;
  final DateTime? requestedAt;
  final DateTime? respondedAt;
  final DateTime? updatedAt;

  const SocialRelation({
    required this.state,
    required this.rawStatus,
    required this.requestDirection,
    required this.canChat,
    required this.canCall,
    required this.canSendRequest,
    required this.blockedByMe,
    required this.blockedByOther,
    required this.otherUserId,
    required this.initiatorUserId,
    required this.requestedAt,
    required this.respondedAt,
    required this.updatedAt,
  });

  bool get isAccepted => state == 'accepted';
  bool get isPendingOutgoing => state == 'pending_outgoing';
  bool get isPendingIncoming => state == 'pending_incoming';
  bool get isBlockedByMe => state == 'blocked_by_me' || blockedByMe;
  bool get isBlockedByOther => state == 'blocked_by_other' || blockedByOther;
  bool get isBlocked => isBlockedByMe || isBlockedByOther;
  bool get isNone => state == 'none';

  factory SocialRelation.fromJson(Map<String, dynamic> j) {
    final state = parseString(j['state'], fallback: 'none');
    return SocialRelation(
      state: state.isEmpty ? 'none' : state,
      rawStatus: parseNullableString(j['rawStatus'] ?? j['raw_status']),
      requestDirection: parseNullableString(
        j['requestDirection'] ?? j['request_direction'],
      ),
      canChat: parseBool(j['canChat'] ?? j['can_chat']),
      canCall: parseBool(j['canCall'] ?? j['can_call']),
      canSendRequest: parseBool(
        j['canSendRequest'] ?? j['can_send_request'],
        fallback: true,
      ),
      blockedByMe: parseBool(j['blockedByMe'] ?? j['blocked_by_me']),
      blockedByOther: parseBool(j['blockedByOther'] ?? j['blocked_by_other']),
      otherUserId: j['otherUserId'] == null && j['other_user_id'] == null
          ? null
          : parseInt(j['otherUserId'] ?? j['other_user_id']),
      initiatorUserId:
          j['initiatorUserId'] == null && j['initiator_user_id'] == null
          ? null
          : parseInt(j['initiatorUserId'] ?? j['initiator_user_id']),
      requestedAt: parseNullableDateTime(j['requestedAt'] ?? j['requested_at']),
      respondedAt: parseNullableDateTime(j['respondedAt'] ?? j['responded_at']),
      updatedAt: parseNullableDateTime(j['updatedAt'] ?? j['updated_at']),
    );
  }
}

class SocialUserNotificationPreference {
  final bool enabled;
  final DateTime? mutedUntil;

  const SocialUserNotificationPreference({
    required this.enabled,
    required this.mutedUntil,
  });

  factory SocialUserNotificationPreference.fromJson(Map<String, dynamic> j) =>
      SocialUserNotificationPreference(
        enabled: parseBool(j['enabled'], fallback: true),
        mutedUntil: parseNullableDateTime(j['mutedUntil'] ?? j['muted_until']),
      );
}

class SocialSuperAdminControls {
  final bool targetIsSuperAdmin;
  final bool accountDisabled;
  final bool isCompoundManager;
  final bool isBuildingManager;
  final bool isBlockManager;
  final String? compoundCode;
  final String? buildingCode;
  final String? blockCode;

  const SocialSuperAdminControls({
    required this.targetIsSuperAdmin,
    required this.accountDisabled,
    required this.isCompoundManager,
    required this.isBuildingManager,
    required this.isBlockManager,
    required this.compoundCode,
    required this.buildingCode,
    required this.blockCode,
  });

  factory SocialSuperAdminControls.fromJson(
    Map<String, dynamic> j,
  ) => SocialSuperAdminControls(
    targetIsSuperAdmin: parseBool(
      j['targetIsSuperAdmin'] ?? j['target_is_super_admin'],
    ),
    accountDisabled: parseBool(j['accountDisabled'] ?? j['account_disabled']),
    isCompoundManager: parseBool(
      j['isCompoundManager'] ?? j['is_compound_manager'],
    ),
    isBuildingManager: parseBool(
      j['isBuildingManager'] ?? j['is_building_manager'],
    ),
    isBlockManager: parseBool(j['isBlockManager'] ?? j['is_block_manager']),
    compoundCode: parseNullableString(j['compoundCode'] ?? j['compound_code']),
    buildingCode: parseNullableString(j['buildingCode'] ?? j['building_code']),
    blockCode: parseNullableString(j['blockCode'] ?? j['block_code']),
  );
}

class SocialUserProfile {
  final int id;
  final String? username;
  final String fullName;
  final String role;
  final bool isSuperAdmin;
  final bool accountDisabled;
  final bool viewerIsSuperAdmin;
  final String bio;
  final String? workTitle;
  final String? workCompany;
  final int? age;
  final String? imageUrl;
  final String? phone;
  final bool showPhone;
  final bool postsPublic;
  final bool storiesPublic;
  final bool relationsPublic;
  final bool accountPrivate;
  final bool contentPrivate;
  final String onlineStatusVisibility;
  final String lastSeenVisibility;
  final bool readReceiptsEnabled;
  final bool typingIndicatorsEnabled;
  final DateTime? coreProfileLockedUntil;
  final String? localContext;
  final Map<String, dynamic>? localContextMeta;
  final String? accountLabelKey;
  final List<String> badges;
  final bool isResidentVerified;
  final bool isMerchantVerified;
  final bool isPremiumMember;
  final bool isCarSeller;
  final bool isPropertySeller;
  final bool premiumBadgeVisible;
  final Map<String, dynamic> tabs;
  final DateTime? joinedAt;
  final bool isMe;
  final SocialUserNotificationPreference? notificationPreference;
  final SocialSuperAdminControls? superAdminControls;
  final SocialRelation relation;
  final SocialUserPostStats stats;

  const SocialUserProfile({
    required this.id,
    this.username,
    required this.fullName,
    required this.role,
    required this.isSuperAdmin,
    required this.accountDisabled,
    required this.viewerIsSuperAdmin,
    required this.bio,
    required this.workTitle,
    required this.workCompany,
    required this.age,
    required this.imageUrl,
    required this.phone,
    required this.showPhone,
    required this.postsPublic,
    required this.storiesPublic,
    required this.relationsPublic,
    this.accountPrivate = false,
    this.contentPrivate = false,
    this.onlineStatusVisibility = 'connections',
    this.lastSeenVisibility = 'connections',
    this.readReceiptsEnabled = true,
    this.typingIndicatorsEnabled = true,
    required this.coreProfileLockedUntil,
    required this.localContext,
    required this.localContextMeta,
    required this.accountLabelKey,
    required this.badges,
    required this.isResidentVerified,
    required this.isMerchantVerified,
    required this.isPremiumMember,
    required this.isCarSeller,
    required this.isPropertySeller,
    required this.premiumBadgeVisible,
    required this.tabs,
    required this.joinedAt,
    required this.isMe,
    required this.notificationPreference,
    required this.superAdminControls,
    required this.relation,
    required this.stats,
  });

  factory SocialUserProfile.fromJson(Map<String, dynamic> j) {
    final privacy = Map<String, dynamic>.from(
      j['privacy'] as Map? ?? const <String, dynamic>{},
    );
    final tabs = Map<String, dynamic>.from(
      j['tabs'] as Map? ?? const <String, dynamic>{},
    );
    final localContextMetaRaw = j['localContext'] ?? j['local_context'];
    final notificationRaw =
        j['notificationPreference'] ?? j['notification_preference'];
    final controlsRaw = j['superAdminControls'] ?? j['super_admin_controls'];
    return SocialUserProfile(
      id: parseInt(j['id']),
      username: parseNullableString(j['username']),
      fullName: parseString(j['fullName'] ?? j['full_name']),
      role: parseString(j['role'], fallback: 'user'),
      isSuperAdmin: parseBool(j['isSuperAdmin'] ?? j['is_super_admin']),
      accountDisabled: parseBool(j['accountDisabled'] ?? j['account_disabled']),
      viewerIsSuperAdmin: parseBool(
        j['viewerIsSuperAdmin'] ?? j['viewer_is_super_admin'],
      ),
      bio: parseString(j['bio'], fallback: ''),
      workTitle: parseNullableString(j['workTitle'] ?? j['work_title']),
      workCompany: parseNullableString(j['workCompany'] ?? j['work_company']),
      age: j['age'] == null && j['social_age'] == null
          ? null
          : parseInt(j['age'] ?? j['social_age']),
      imageUrl: parseNullableString(j['imageUrl'] ?? j['image_url']),
      phone: parseNullableString(j['phone']),
      showPhone: parseBool(
        privacy['showPhone'] ?? privacy['show_phone'] ?? j['showPhone'],
      ),
      postsPublic: parseBool(
        privacy['postsPublic'] ?? privacy['posts_public'] ?? j['postsPublic'],
        fallback: true,
      ),
      storiesPublic: parseBool(
        privacy['storiesPublic'] ??
            privacy['stories_public'] ??
            j['storiesPublic'],
        fallback: true,
      ),
      relationsPublic: parseBool(
        privacy['relationsPublic'] ??
            privacy['relations_public'] ??
            j['relationsPublic'] ??
            j['relations_public'],
        fallback: true,
      ),
      accountPrivate: parseBool(
        privacy['accountPrivate'] ??
            privacy['account_private'] ??
            j['accountPrivate'] ??
            j['socialAccountPrivate'] ??
            j['social_account_private'],
      ),
      contentPrivate: parseBool(j['contentPrivate'] ?? j['content_private']),
      onlineStatusVisibility: parseString(
        privacy['onlineStatusVisibility'] ??
            privacy['online_status_visibility'] ??
            j['onlineStatusVisibility'] ??
            j['social_online_visibility'],
        fallback: 'connections',
      ),
      lastSeenVisibility: parseString(
        privacy['lastSeenVisibility'] ??
            privacy['last_seen_visibility'] ??
            j['lastSeenVisibility'] ??
            j['social_last_seen_visibility'],
        fallback: 'connections',
      ),
      readReceiptsEnabled: parseBool(
        privacy['readReceiptsEnabled'] ??
            privacy['read_receipts_enabled'] ??
            j['readReceiptsEnabled'] ??
            j['social_read_receipts_enabled'],
        fallback: true,
      ),
      typingIndicatorsEnabled: parseBool(
        privacy['typingIndicatorsEnabled'] ??
            privacy['typing_indicators_enabled'] ??
            j['typingIndicatorsEnabled'] ??
            j['social_typing_indicators_enabled'],
        fallback: true,
      ),
      coreProfileLockedUntil: parseNullableDateTime(
        j['coreProfileLockedUntil'] ?? j['core_profile_locked_until'],
      ),
      localContext: _parseLocalContextLabel(localContextMetaRaw),
      localContextMeta: localContextMetaRaw is Map
          ? Map<String, dynamic>.from(localContextMetaRaw)
          : null,
      accountLabelKey: parseNullableString(
        j['accountLabelKey'] ?? j['account_label_key'],
      ),
      badges: _parseBadgeKeys(j['badges']),
      isResidentVerified: parseBool(
        j['isResidentVerified'] ?? j['is_resident_verified'],
      ),
      isMerchantVerified: parseBool(
        j['isMerchantVerified'] ?? j['is_merchant_verified'],
      ),
      isPremiumMember: parseBool(
        j['isPremiumMember'] ?? j['is_premium_member'],
      ),
      isCarSeller: parseBool(j['isCarSeller'] ?? j['is_car_seller']),
      isPropertySeller: parseBool(
        j['isPropertySeller'] ?? j['is_property_seller'],
      ),
      premiumBadgeVisible: parseBool(
        j['premiumBadgeVisible'] ?? j['premium_badge_visible'],
      ),
      tabs: tabs,
      joinedAt: parseNullableDateTime(j['joinedAt'] ?? j['joined_at']),
      isMe: parseBool(j['isMe'] ?? j['is_me']),
      notificationPreference: notificationRaw is Map
          ? SocialUserNotificationPreference.fromJson(
              Map<String, dynamic>.from(notificationRaw),
            )
          : null,
      superAdminControls: controlsRaw is Map
          ? SocialSuperAdminControls.fromJson(
              Map<String, dynamic>.from(controlsRaw),
            )
          : null,
      relation: SocialRelation.fromJson(
        Map<String, dynamic>.from(j['relation'] as Map? ?? const {}),
      ),
      stats: SocialUserPostStats.fromJson(
        Map<String, dynamic>.from(j['stats'] as Map? ?? const {}),
      ),
    );
  }
}

class SocialStoryHighlight {
  final int id;
  final int ownerUserId;
  final String title;
  final DateTime? createdAt;
  final SocialStory story;

  const SocialStoryHighlight({
    required this.id,
    required this.ownerUserId,
    required this.title,
    required this.createdAt,
    required this.story,
  });

  factory SocialStoryHighlight.fromJson(Map<String, dynamic> j) =>
      SocialStoryHighlight(
        id: parseInt(j['id']),
        ownerUserId: parseInt(j['ownerUserId'] ?? j['owner_user_id']),
        title: parseString(j['title'], fallback: ''),
        createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
        story: SocialStory.fromJson(
          Map<String, dynamic>.from(j['story'] as Map? ?? const {}),
        ),
      );
}

class SocialChatReplyPreview {
  final int id;
  final int senderUserId;
  final String? senderUsername;
  final String senderFullName;
  final String body;
  final String? attachmentKind;
  final String? attachmentName;

  const SocialChatReplyPreview({
    required this.id,
    required this.senderUserId,
    this.senderUsername,
    required this.senderFullName,
    required this.body,
    required this.attachmentKind,
    required this.attachmentName,
  });

  factory SocialChatReplyPreview.fromJson(Map<String, dynamic> j) =>
      SocialChatReplyPreview(
        id: parseInt(j['id']),
        senderUserId: parseInt(j['senderUserId'] ?? j['sender_user_id']),
        senderUsername: parseNullableString(
          j['senderUsername'] ?? j['sender_username'],
        ),
        senderFullName: parseString(
          j['senderFullName'] ?? j['sender_full_name'],
        ),
        body: parseString(j['body']),
        attachmentKind: parseNullableString(
          j['attachmentKind'] ?? j['attachment_kind'],
        ),
        attachmentName: parseNullableString(
          j['attachmentName'] ?? j['attachment_name'],
        ),
      );

  String get previewText {
    if (body.trim().isNotEmpty) return body.trim();
    if ((attachmentName ?? '').trim().isNotEmpty) return attachmentName!.trim();
    switch ((attachmentKind ?? '').trim().toLowerCase()) {
      case 'image':
        return 'صورة';
      case 'video':
        return 'فيديو';
      case 'audio':
        return 'رسالة صوتية';
      default:
        return 'ملف';
    }
  }
}

class SocialChatAttachment {
  final String url;
  final String kind;
  final String? name;
  final String? mimeType;
  final int? sizeBytes;
  final int? durationMs;

  const SocialChatAttachment({
    required this.url,
    required this.kind,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.durationMs,
  });

  factory SocialChatAttachment.fromJson(Map<String, dynamic> j) =>
      SocialChatAttachment(
        url: parseString(j['url'] ?? j['attachmentUrl'] ?? j['attachment_url']),
        kind: parseString(
          j['kind'] ?? j['attachmentKind'] ?? j['attachment_kind'],
          fallback: 'file',
        ),
        name: parseNullableString(
          j['name'] ?? j['attachmentName'] ?? j['attachment_name'],
        ),
        mimeType: parseNullableString(
          j['mimeType'] ?? j['attachmentMimeType'] ?? j['attachment_mime_type'],
        ),
        sizeBytes: parseNullableInt(
          j['sizeBytes'] ?? j['attachment_size_bytes'],
        ),
        durationMs: parseNullableInt(
          j['durationMs'] ??
              j['attachmentDurationMs'] ??
              j['attachment_duration_ms'],
        ),
      );

  String get previewLabel {
    switch (kind.trim().toLowerCase()) {
      case 'image':
        return 'صورة';
      case 'video':
        return 'فيديو';
      case 'audio':
        return 'رسالة صوتية';
      default:
        return (name ?? '').trim().isNotEmpty ? name!.trim() : 'ملف';
    }
  }
}

class SocialSharedEntity {
  final String type;
  final int id;
  final Map<String, dynamic>? snapshot;

  const SocialSharedEntity({
    required this.type,
    required this.id,
    required this.snapshot,
  });

  factory SocialSharedEntity.fromJson(Map<String, dynamic> j) =>
      SocialSharedEntity(
        type: parseString(j['type'], fallback: 'post'),
        id: parseInt(j['id']),
        snapshot: j['snapshot'] is Map
            ? Map<String, dynamic>.from(j['snapshot'] as Map)
            : j['sharedSnapshot'] is Map
            ? Map<String, dynamic>.from(j['sharedSnapshot'] as Map)
            : j['shared_snapshot_json'] is Map
            ? Map<String, dynamic>.from(j['shared_snapshot_json'] as Map)
            : null,
      );

  Map<String, dynamic> get _snapshot => snapshot ?? const <String, dynamic>{};

  Map<String, dynamic> get _authorSnapshot => _snapshot['author'] is Map
      ? Map<String, dynamic>.from(_snapshot['author'] as Map)
      : const <String, dynamic>{};

  String get previewLabel {
    switch (type.trim().toLowerCase()) {
      case 'location':
        return 'موقع مشارك';
      case 'reel':
        return 'ريل مشارك';
      case 'story':
        return 'ستوري مشارك';
      case 'profile':
      case 'user':
        return 'ملف شخصي';
      case 'review':
      case 'merchant_review':
        return 'مراجعة مشاركة';
      case 'car_listing':
        return 'إعلان سيارة';
      case 'real_estate_listing':
        return 'إعلان عقار';
      default:
        return 'منشور مشارك';
    }
  }

  String get title {
    final source = _snapshot;
    final normalizedType = type.trim().toLowerCase();
    final value = parseString(
      normalizedType == 'profile' || normalizedType == 'user'
          ? source['authorName'] ??
                source['author_name'] ??
                source['fullName'] ??
                source['full_name'] ??
                _authorSnapshot['fullName'] ??
                _authorSnapshot['full_name'] ??
                source['name'] ??
                source['title']
          : source['title'] ?? source['name'],
    );
    return value.isNotEmpty ? value : previewLabel;
  }

  String? get subtitle {
    final value = parseNullableString(
      _snapshot['subtitle'] ??
          _snapshot['caption'] ??
          _snapshot['description'] ??
          _snapshot['body'],
    );
    if (value == null || value.trim() == title.trim()) return null;
    return value;
  }

  String? get imageUrl => parseNullableString(
    _snapshot['imageUrl'] ??
        _snapshot['posterUrl'] ??
        _snapshot['thumbnailUrl'] ??
        _snapshot['mediaUrl'] ??
        _snapshot['authorImageUrl'] ??
        _snapshot['authorAvatarUrl'] ??
        _authorSnapshot['imageUrl'] ??
        _authorSnapshot['image_url'],
  );

  String? get authorDisplayName => parseNullableString(
    _snapshot['authorDisplayName'] ??
        _snapshot['authorName'] ??
        _snapshot['authorFullName'] ??
        _snapshot['fullName'] ??
        _authorSnapshot['fullName'] ??
        _authorSnapshot['full_name'] ??
        _authorSnapshot['name'],
  );

  String? get authorUsername {
    final value = parseNullableString(
      _snapshot['authorUsername'] ??
          _snapshot['username'] ??
          _snapshot['author_handle'] ??
          _authorSnapshot['username'] ??
          _authorSnapshot['handle'],
    );
    if (value == null) return null;
    final normalized = value.replaceFirst(RegExp(r'^@+'), '').trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? get authorAvatarUrl => parseNullableString(
    _snapshot['authorAvatarUrl'] ??
        _snapshot['authorImageUrl'] ??
        _snapshot['author_image_url'] ??
        _authorSnapshot['imageUrl'] ??
        _authorSnapshot['image_url'] ??
        _authorSnapshot['avatarUrl'] ??
        _authorSnapshot['avatar_url'],
  );

  num? get price {
    final raw = (snapshot ?? const <String, dynamic>{})['price'];
    if (raw == null) return null;
    return num.tryParse('$raw');
  }

  double? get latitude {
    final raw = (snapshot ?? const <String, dynamic>{})['latitude'];
    if (raw == null) return null;
    return double.tryParse('$raw');
  }

  double? get longitude {
    final raw = (snapshot ?? const <String, dynamic>{})['longitude'];
    if (raw == null) return null;
    return double.tryParse('$raw');
  }

  String? get address => parseNullableString(
    (snapshot ?? const <String, dynamic>{})['address'] ??
        (snapshot ?? const <String, dynamic>{})['label'],
  );
}

class SocialThreadPresence {
  final bool isOnline;
  final DateTime? lastSeenAt;
  final bool canSeeOnlineStatus;
  final bool canSeeLastSeen;
  final bool canSeeReadReceipts;
  final bool canSeeTypingIndicators;

  const SocialThreadPresence({
    required this.isOnline,
    required this.lastSeenAt,
    required this.canSeeOnlineStatus,
    required this.canSeeLastSeen,
    required this.canSeeReadReceipts,
    required this.canSeeTypingIndicators,
  });

  factory SocialThreadPresence.fromJson(Map<String, dynamic> j) =>
      SocialThreadPresence(
        isOnline: parseBool(j['isOnline'] ?? j['is_online']),
        lastSeenAt: parseNullableDateTime(j['lastSeenAt'] ?? j['last_seen_at']),
        canSeeOnlineStatus: parseBool(
          j['canSeeOnlineStatus'] ?? j['can_see_online_status'],
        ),
        canSeeLastSeen: parseBool(
          j['canSeeLastSeen'] ?? j['can_see_last_seen'],
        ),
        canSeeReadReceipts: parseBool(
          j['canSeeReadReceipts'] ?? j['can_see_read_receipts'],
        ),
        canSeeTypingIndicators: parseBool(
          j['canSeeTypingIndicators'] ?? j['can_see_typing_indicators'],
        ),
      );

  SocialThreadPresence copyWith({
    bool? isOnline,
    DateTime? lastSeenAt,
    bool? canSeeOnlineStatus,
    bool? canSeeLastSeen,
    bool? canSeeReadReceipts,
    bool? canSeeTypingIndicators,
  }) {
    return SocialThreadPresence(
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      canSeeOnlineStatus: canSeeOnlineStatus ?? this.canSeeOnlineStatus,
      canSeeLastSeen: canSeeLastSeen ?? this.canSeeLastSeen,
      canSeeReadReceipts: canSeeReadReceipts ?? this.canSeeReadReceipts,
      canSeeTypingIndicators:
          canSeeTypingIndicators ?? this.canSeeTypingIndicators,
    );
  }
}

class SocialScheduledChatMessage {
  final int id;
  final int threadId;
  final int senderUserId;
  final String body;
  final SocialChatReplyPreview? replyToMessage;
  final SocialChatAttachment? attachment;
  final SocialSharedEntity? sharedEntity;
  final DateTime? scheduledFor;
  final DateTime? createdAt;
  final DateTime? sentAt;
  final int? sentMessageId;
  final String status;
  final int attempts;
  final String? lastErrorCode;

  const SocialScheduledChatMessage({
    required this.id,
    required this.threadId,
    required this.senderUserId,
    required this.body,
    required this.replyToMessage,
    required this.attachment,
    required this.sharedEntity,
    required this.scheduledFor,
    required this.createdAt,
    required this.sentAt,
    required this.sentMessageId,
    required this.status,
    required this.attempts,
    required this.lastErrorCode,
  });

  factory SocialScheduledChatMessage.fromJson(
    Map<String, dynamic> j,
  ) => SocialScheduledChatMessage(
    id: parseInt(j['id']),
    threadId: parseInt(j['threadId'] ?? j['thread_id']),
    senderUserId: parseInt(j['senderUserId'] ?? j['sender_user_id']),
    body: parseString(j['body']),
    replyToMessage:
        j['replyToMessage'] is Map ||
            j['reply_to_message'] is Map ||
            j['replyMessageId'] != null ||
            j['reply_message_id'] != null
        ? SocialChatReplyPreview.fromJson(
            Map<String, dynamic>.from(
              (j['replyToMessage'] ?? j['reply_to_message']) as Map? ??
                  <String, dynamic>{
                    'id': j['replyMessageId'] ?? j['reply_message_id'],
                    'senderUserId':
                        j['replySenderUserId'] ?? j['reply_sender_user_id'],
                    'senderUsername':
                        j['replySenderUsername'] ?? j['reply_sender_username'],
                    'senderFullName':
                        j['replySenderFullName'] ?? j['reply_sender_full_name'],
                    'body': j['replyBody'] ?? j['reply_body'],
                    'attachmentKind':
                        j['replyAttachmentKind'] ?? j['reply_attachment_kind'],
                    'attachmentName':
                        j['replyAttachmentName'] ?? j['reply_attachment_name'],
                  },
            ),
          )
        : null,
    attachment:
        j['attachment'] is Map ||
            j['attachmentUrl'] != null ||
            j['attachment_url'] != null
        ? SocialChatAttachment.fromJson(
            Map<String, dynamic>.from(
              j['attachment'] as Map? ??
                  <String, dynamic>{
                    'attachmentUrl': j['attachmentUrl'] ?? j['attachment_url'],
                    'attachmentKind':
                        j['attachmentKind'] ?? j['attachment_kind'],
                    'attachmentName':
                        j['attachmentName'] ?? j['attachment_name'],
                    'attachmentMimeType':
                        j['attachmentMimeType'] ?? j['attachment_mime_type'],
                    'sizeBytes': j['sizeBytes'] ?? j['attachment_size_bytes'],
                    'attachmentDurationMs':
                        j['attachmentDurationMs'] ??
                        j['attachment_duration_ms'],
                  },
            ),
          )
        : null,
    sharedEntity:
        j['sharedEntity'] is Map ||
            j['shared_entity'] is Map ||
            j['sharedEntityType'] != null ||
            j['shared_entity_type'] != null
        ? SocialSharedEntity.fromJson(
            Map<String, dynamic>.from(
              (j['sharedEntity'] ?? j['shared_entity']) as Map? ??
                  <String, dynamic>{
                    'type':
                        j['sharedEntityType'] ??
                        j['shared_entity_type'] ??
                        'post',
                    'id': j['sharedEntityId'] ?? j['shared_entity_id'],
                    'snapshot':
                        j['sharedSnapshot'] ??
                        j['shared_snapshot'] ??
                        j['sharedSnapshotJson'] ??
                        j['shared_snapshot_json'],
                  },
            ),
          )
        : null,
    scheduledFor: parseNullableDateTime(
      j['scheduledFor'] ?? j['scheduled_for'],
    ),
    createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
    sentAt: parseNullableDateTime(j['sentAt'] ?? j['sent_at']),
    sentMessageId: parseNullableInt(j['sentMessageId'] ?? j['sent_message_id']),
    status: parseString(j['status'], fallback: 'scheduled'),
    attempts: parseInt(j['attempts']),
    lastErrorCode: parseNullableString(
      j['lastErrorCode'] ?? j['last_error_code'],
    ),
  );

  bool get isFailed => status.trim().toLowerCase() == 'failed';
  bool get isProcessing => status.trim().toLowerCase() == 'processing';

  String get previewText {
    if (body.trim().isNotEmpty) return body.trim();
    return attachment?.previewLabel ?? sharedEntity?.previewLabel ?? 'رسالة';
  }
}

class SocialBusinessContext {
  final String type;
  final int id;
  final String status;
  final bool isAvailable;
  final int? ownerId;
  final String title;
  final String? subtitle;
  final num? price;
  final String? imageUrl;
  final String? posterUrl;

  const SocialBusinessContext({
    required this.type,
    required this.id,
    required this.status,
    required this.isAvailable,
    required this.ownerId,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.imageUrl,
    required this.posterUrl,
  });

  factory SocialBusinessContext.fromJson(Map<String, dynamic> j) =>
      SocialBusinessContext(
        type: parseString(j['type'], fallback: 'none'),
        id: parseInt(j['id']),
        status: parseString(j['status'], fallback: 'active'),
        isAvailable: parseBool(j['isAvailable'] ?? j['is_available']),
        ownerId: parseNullableInt(j['ownerId'] ?? j['owner_id']),
        title: parseString(j['title']),
        subtitle: parseNullableString(j['subtitle']),
        price: j['price'] == null ? null : num.tryParse('${j['price']}'),
        imageUrl: parseNullableString(j['imageUrl'] ?? j['image_url']),
        posterUrl: parseNullableString(j['posterUrl'] ?? j['poster_url']),
      );
}

class SocialThreadState {
  final bool muted;
  final DateTime? mutedUntil;
  final DateTime? pinnedAt;
  final String themeKey;
  final String inboxBucket;
  final String requestStatus;
  final DateTime? acceptedAt;
  final DateTime? rejectedAt;
  final int? lastReadMessageId;
  final int? lastDeliveredMessageId;
  final int unreadCount;

  const SocialThreadState({
    required this.muted,
    required this.mutedUntil,
    required this.pinnedAt,
    required this.themeKey,
    required this.inboxBucket,
    required this.requestStatus,
    required this.acceptedAt,
    required this.rejectedAt,
    required this.lastReadMessageId,
    required this.lastDeliveredMessageId,
    required this.unreadCount,
  });

  factory SocialThreadState.fromJson(Map<String, dynamic> j) =>
      SocialThreadState(
        muted: parseBool(j['muted']),
        mutedUntil: parseNullableDateTime(j['mutedUntil'] ?? j['muted_until']),
        pinnedAt: parseNullableDateTime(j['pinnedAt'] ?? j['pinned_at']),
        themeKey: parseString(
          j['themeKey'] ?? j['theme_key'],
          fallback: 'default',
        ),
        inboxBucket: parseString(
          j['inboxBucket'] ?? j['inbox_bucket'],
          fallback: 'primary',
        ),
        requestStatus: parseString(
          j['requestStatus'] ?? j['request_status'],
          fallback: 'accepted',
        ),
        acceptedAt: parseNullableDateTime(j['acceptedAt'] ?? j['accepted_at']),
        rejectedAt: parseNullableDateTime(j['rejectedAt'] ?? j['rejected_at']),
        lastReadMessageId: parseNullableInt(
          j['lastReadMessageId'] ?? j['last_read_message_id'],
        ),
        lastDeliveredMessageId: parseNullableInt(
          j['lastDeliveredMessageId'] ?? j['last_delivered_message_id'],
        ),
        unreadCount: parseInt(j['unreadCount'] ?? j['unread_count']),
      );

  SocialThreadState copyWith({
    bool? muted,
    DateTime? mutedUntil,
    DateTime? pinnedAt,
    String? themeKey,
    String? inboxBucket,
    String? requestStatus,
    DateTime? acceptedAt,
    DateTime? rejectedAt,
    int? lastReadMessageId,
    int? lastDeliveredMessageId,
    int? unreadCount,
  }) {
    return SocialThreadState(
      muted: muted ?? this.muted,
      mutedUntil: mutedUntil ?? this.mutedUntil,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      themeKey: themeKey ?? this.themeKey,
      inboxBucket: inboxBucket ?? this.inboxBucket,
      requestStatus: requestStatus ?? this.requestStatus,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
      lastDeliveredMessageId:
          lastDeliveredMessageId ?? this.lastDeliveredMessageId,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class SocialChatMessageTranslation {
  final int id;
  final int messageId;
  final String targetLanguage;
  final String? sourceLanguage;
  final String translatedText;
  final String provider;
  final String? modelName;
  final DateTime? sourceVersionAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SocialChatMessageTranslation({
    required this.id,
    required this.messageId,
    required this.targetLanguage,
    required this.sourceLanguage,
    required this.translatedText,
    required this.provider,
    required this.modelName,
    required this.sourceVersionAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SocialChatMessageTranslation.fromJson(Map<String, dynamic> j) =>
      SocialChatMessageTranslation(
        id: parseInt(j['id']),
        messageId: parseInt(j['messageId'] ?? j['message_id']),
        targetLanguage: parseString(
          j['targetLanguage'] ?? j['target_language'],
          fallback: 'en',
        ),
        sourceLanguage: parseNullableString(
          j['sourceLanguage'] ?? j['source_language'],
        ),
        translatedText: parseString(
          j['translatedText'] ?? j['translated_text'],
        ),
        provider: parseString(j['provider'], fallback: 'openai'),
        modelName: parseNullableString(j['modelName'] ?? j['model_name']),
        sourceVersionAt: parseNullableDateTime(
          j['sourceVersionAt'] ?? j['source_version_at'],
        ),
        createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
        updatedAt: parseNullableDateTime(j['updatedAt'] ?? j['updated_at']),
      );
}

class SocialChatMessage {
  final int id;
  final int threadId;
  final int senderUserId;
  final String body;
  final String? clientMessageId;
  final SocialChatReplyPreview? replyToMessage;
  final SocialChatAttachment? attachment;
  final SocialSharedEntity? sharedEntity;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime? pinnedAt;
  final int? pinnedByUserId;
  final bool isDeleted;
  final bool isMine;
  final Map<String, int> reactionCounts;
  final int reactionTotalCount;
  final String? myReaction;
  final bool deliveredToPeer;
  final bool readByPeer;
  final SocialAuthor sender;

  const SocialChatMessage({
    required this.id,
    required this.threadId,
    required this.senderUserId,
    required this.body,
    this.clientMessageId,
    required this.replyToMessage,
    required this.attachment,
    required this.sharedEntity,
    required this.createdAt,
    required this.updatedAt,
    required this.editedAt,
    required this.deletedAt,
    required this.pinnedAt,
    required this.pinnedByUserId,
    required this.isDeleted,
    required this.isMine,
    required this.reactionCounts,
    required this.reactionTotalCount,
    required this.myReaction,
    required this.deliveredToPeer,
    required this.readByPeer,
    required this.sender,
  });

  factory SocialChatMessage.fromJson(
    Map<String, dynamic> j,
  ) => SocialChatMessage(
    id: parseInt(j['id']),
    threadId: parseInt(j['threadId'] ?? j['thread_id']),
    senderUserId: parseInt(j['senderUserId'] ?? j['sender_user_id']),
    body: parseString(j['body']),
    clientMessageId: parseNullableString(
      j['clientMessageId'] ?? j['client_message_id'],
    ),
    replyToMessage: j['replyToMessage'] is Map || j['reply_to_message'] is Map
        ? SocialChatReplyPreview.fromJson(
            Map<String, dynamic>.from(
              (j['replyToMessage'] ?? j['reply_to_message']) as Map,
            ),
          )
        : null,
    attachment:
        j['attachment'] is Map ||
            j['attachmentUrl'] != null ||
            j['attachment_url'] != null
        ? SocialChatAttachment.fromJson(
            Map<String, dynamic>.from(
              j['attachment'] as Map? ??
                  <String, dynamic>{
                    'attachmentUrl': j['attachmentUrl'] ?? j['attachment_url'],
                    'attachmentKind':
                        j['attachmentKind'] ?? j['attachment_kind'],
                    'attachmentName':
                        j['attachmentName'] ?? j['attachment_name'],
                    'attachmentMimeType':
                        j['attachmentMimeType'] ?? j['attachment_mime_type'],
                    'sizeBytes': j['sizeBytes'] ?? j['attachment_size_bytes'],
                  },
            ),
          )
        : null,
    sharedEntity:
        j['sharedEntity'] is Map ||
            j['shared_entity'] is Map ||
            j['sharedEntityType'] != null ||
            j['shared_entity_type'] != null
        ? SocialSharedEntity.fromJson(
            Map<String, dynamic>.from(
              (j['sharedEntity'] ?? j['shared_entity']) as Map? ??
                  <String, dynamic>{
                    'type':
                        j['sharedEntityType'] ??
                        j['shared_entity_type'] ??
                        'post',
                    'id': j['sharedEntityId'] ?? j['shared_entity_id'],
                    'snapshot':
                        j['sharedSnapshot'] ??
                        j['shared_snapshot'] ??
                        j['sharedSnapshotJson'] ??
                        j['shared_snapshot_json'],
                  },
            ),
          )
        : null,
    createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
    updatedAt: parseNullableDateTime(j['updatedAt'] ?? j['updated_at']),
    editedAt: parseNullableDateTime(j['editedAt'] ?? j['edited_at']),
    deletedAt: parseNullableDateTime(j['deletedAt'] ?? j['deleted_at']),
    pinnedAt: parseNullableDateTime(j['pinnedAt'] ?? j['pinned_at']),
    pinnedByUserId: parseNullableInt(
      j['pinnedByUserId'] ?? j['pinned_by_user_id'],
    ),
    isDeleted: parseBool(j['isDeleted'] ?? j['is_deleted']),
    isMine: parseBool(j['isMine'] ?? j['is_mine']),
    reactionCounts: _parseReactionCounts(j['reactions']),
    reactionTotalCount: _parseReactionTotalCount(j['reactions']),
    myReaction: _parseMyReaction(j['reactions']),
    deliveredToPeer: parseBool(j['deliveredToPeer'] ?? j['delivered_to_peer']),
    readByPeer: parseBool(j['readByPeer'] ?? j['read_by_peer']),
    sender: SocialAuthor.fromJson(
      Map<String, dynamic>.from(j['sender'] as Map? ?? const {}),
    ),
  );

  SocialChatMessage copyWith({
    String? body,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? editedAt,
    DateTime? deletedAt,
    DateTime? pinnedAt,
    int? pinnedByUserId,
    bool? isDeleted,
    bool? isMine,
    SocialChatReplyPreview? replyToMessage,
    SocialChatAttachment? attachment,
    SocialSharedEntity? sharedEntity,
    String? clientMessageId,
    bool clearClientMessageId = false,
    Map<String, int>? reactionCounts,
    int? reactionTotalCount,
    String? myReaction,
    bool clearMyReaction = false,
    bool? deliveredToPeer,
    bool? readByPeer,
    SocialAuthor? sender,
  }) {
    return SocialChatMessage(
      id: id,
      threadId: threadId,
      senderUserId: senderUserId,
      body: body ?? this.body,
      clientMessageId: clearClientMessageId
          ? null
          : (clientMessageId ?? this.clientMessageId),
      replyToMessage: replyToMessage ?? this.replyToMessage,
      attachment: attachment ?? this.attachment,
      sharedEntity: sharedEntity ?? this.sharedEntity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      pinnedByUserId: pinnedByUserId ?? this.pinnedByUserId,
      isDeleted: isDeleted ?? this.isDeleted,
      isMine: isMine ?? this.isMine,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      reactionTotalCount: reactionTotalCount ?? this.reactionTotalCount,
      myReaction: clearMyReaction ? null : (myReaction ?? this.myReaction),
      deliveredToPeer: deliveredToPeer ?? this.deliveredToPeer,
      readByPeer: readByPeer ?? this.readByPeer,
      sender: sender ?? this.sender,
    );
  }

  SocialChatMessage resolvedForViewer({
    required int? viewerUserId,
    SocialAuthor? selfAuthor,
    SocialAuthor? peerAuthor,
  }) {
    final computedMine = viewerUserId != null && viewerUserId > 0
        ? senderUserId == viewerUserId
        : isMine;
    final fallbackAuthor = computedMine ? selfAuthor : peerAuthor;
    var resolvedSender = sender.mergedWith(fallbackAuthor);
    if (resolvedSender.id <= 0 && senderUserId > 0) {
      resolvedSender = resolvedSender.copyWith(id: senderUserId);
    }
    return copyWith(isMine: computedMine, sender: resolvedSender);
  }

  String get previewText {
    if (body.trim().isNotEmpty) return body.trim();
    return attachment?.previewLabel ?? sharedEntity?.previewLabel ?? 'رسالة';
  }
}

class SocialThreadGroupInfo {
  final int ownerUserId;
  final String title;
  final String? imageUrl;
  final int memberCount;
  final int adminCount;
  final String memberRole;

  const SocialThreadGroupInfo({
    required this.ownerUserId,
    required this.title,
    required this.imageUrl,
    required this.memberCount,
    required this.adminCount,
    required this.memberRole,
  });

  factory SocialThreadGroupInfo.fromJson(Map<String, dynamic> j) =>
      SocialThreadGroupInfo(
        ownerUserId: parseInt(j['ownerUserId'] ?? j['owner_user_id'] ?? 0),
        title: parseString(j['title'], fallback: 'مجموعة'),
        imageUrl: parseNullableString(j['imageUrl'] ?? j['image_url']),
        memberCount: parseInt(j['memberCount'] ?? j['member_count'] ?? 0),
        adminCount: parseInt(j['adminCount'] ?? j['admin_count'] ?? 0),
        memberRole: parseString(
          j['memberRole'] ?? j['member_role'],
          fallback: 'member',
        ),
      );

  bool get canManage => memberRole == 'owner' || memberRole == 'admin';
}

class SocialThreadMember {
  final int userId;
  final String memberRole;
  final int? addedByUserId;
  final DateTime? addedAt;
  final SocialThreadPresence presence;
  final SocialAuthor user;

  const SocialThreadMember({
    required this.userId,
    required this.memberRole,
    required this.addedByUserId,
    required this.addedAt,
    required this.presence,
    required this.user,
  });

  factory SocialThreadMember.fromJson(Map<String, dynamic> j) =>
      SocialThreadMember(
        userId: parseInt(j['userId'] ?? j['user_id']),
        memberRole: parseString(
          j['memberRole'] ?? j['member_role'],
          fallback: 'member',
        ),
        addedByUserId: parseNullableInt(
          j['addedByUserId'] ?? j['added_by_user_id'],
        ),
        addedAt: parseNullableDateTime(j['addedAt'] ?? j['added_at']),
        presence: SocialThreadPresence.fromJson(
          Map<String, dynamic>.from(j['presence'] as Map? ?? const {}),
        ),
        user: SocialAuthor.fromJson(
          Map<String, dynamic>.from(j['user'] as Map? ?? const {}),
        ),
      );

  bool get canManage => memberRole == 'owner' || memberRole == 'admin';
  bool get isOwner => memberRole == 'owner';
}

class SocialChatThread {
  final int id;
  final String threadKind;
  final String contextType;
  final int contextId;
  final String contextStatus;
  final Map<String, dynamic>? contextSnapshot;
  final SocialBusinessContext? context;
  final SocialThreadGroupInfo? group;
  final SocialAuthor peer;
  final String peerPhone;
  final SocialThreadPresence presence;
  final DateTime? lastMessageAt;
  final SocialChatMessage? lastMessage;
  final SocialThreadState state;

  const SocialChatThread({
    required this.id,
    required this.threadKind,
    required this.contextType,
    required this.contextId,
    required this.contextStatus,
    required this.contextSnapshot,
    required this.context,
    required this.group,
    required this.peer,
    required this.peerPhone,
    required this.presence,
    required this.lastMessageAt,
    required this.lastMessage,
    required this.state,
  });

  factory SocialChatThread.fromJson(Map<String, dynamic> j) => SocialChatThread(
    id: parseInt(j['id']),
    threadKind: parseString(
      j['threadKind'] ?? j['thread_kind'],
      fallback: 'private',
    ),
    contextType: parseString(
      j['contextType'] ?? j['context_type'],
      fallback: 'none',
    ),
    contextId: parseInt(j['contextId'] ?? j['context_id'] ?? 0),
    contextStatus: parseString(
      j['contextStatus'] ?? j['context_status'],
      fallback: 'active',
    ),
    contextSnapshot: j['contextSnapshot'] is Map
        ? Map<String, dynamic>.from(j['contextSnapshot'] as Map)
        : j['context_snapshot'] is Map
        ? Map<String, dynamic>.from(j['context_snapshot'] as Map)
        : j['contextSnapshotJson'] is Map
        ? Map<String, dynamic>.from(j['contextSnapshotJson'] as Map)
        : j['context_snapshot_json'] is Map
        ? Map<String, dynamic>.from(j['context_snapshot_json'] as Map)
        : null,
    context: j['context'] is Map || j['businessContext'] is Map
        ? SocialBusinessContext.fromJson(
            Map<String, dynamic>.from(
              (j['context'] ?? j['businessContext']) as Map,
            ),
          )
        : null,
    group:
        j['group'] is Map ||
            j['groupInfo'] is Map ||
            j['groupTitle'] != null ||
            j['group_title'] != null
        ? SocialThreadGroupInfo.fromJson(
            Map<String, dynamic>.from(
              (j['group'] ?? j['groupInfo']) as Map? ??
                  <String, dynamic>{
                    'ownerUserId':
                        j['groupOwnerUserId'] ?? j['group_owner_user_id'],
                    'title': j['groupTitle'] ?? j['group_title'],
                    'imageUrl': j['groupImageUrl'] ?? j['group_image_url'],
                    'memberCount':
                        j['groupMemberCount'] ?? j['group_member_count'],
                    'adminCount':
                        j['groupAdminCount'] ?? j['group_admin_count'],
                    'memberRole':
                        j['groupMemberRole'] ?? j['group_member_role'],
                  },
            ),
          )
        : null,
    peer: SocialAuthor.fromJson(
      Map<String, dynamic>.from(j['peer'] as Map? ?? const {}),
    ),
    peerPhone: parseString(
      j['peerPhone'] ??
          j['peer_phone'] ??
          (j['peer'] is Map ? (j['peer'] as Map)['phone'] : null),
    ),
    presence: SocialThreadPresence.fromJson(
      Map<String, dynamic>.from(j['presence'] as Map? ?? const {}),
    ),
    lastMessageAt: parseNullableDateTime(
      j['lastMessageAt'] ?? j['last_message_at'],
    ),
    lastMessage: j['lastMessage'] is Map
        ? SocialChatMessage.fromJson(
            Map<String, dynamic>.from(j['lastMessage'] as Map),
          )
        : null,
    state: SocialThreadState.fromJson(
      Map<String, dynamic>.from(j['state'] as Map? ?? const {}),
    ),
  );

  bool get isGroup => threadKind.trim().toLowerCase() == 'group';

  String get displayTitle {
    if (isGroup && (group?.title.trim().isNotEmpty ?? false)) {
      return group!.title.trim();
    }
    final username = (peer.username ?? '').trim();
    if (username.isNotEmpty) {
      return '@$username';
    }
    if (peer.fullName.trim().isNotEmpty) {
      return peer.fullName.trim();
    }
    return peerPhone;
  }

  String? get displayImageUrl =>
      isGroup ? group?.imageUrl ?? peer.imageUrl : peer.imageUrl;

  SocialChatThread copyWith({
    SocialAuthor? peer,
    SocialThreadGroupInfo? group,
    SocialThreadPresence? presence,
    DateTime? lastMessageAt,
    SocialChatMessage? lastMessage,
    SocialThreadState? state,
  }) {
    return SocialChatThread(
      id: id,
      threadKind: threadKind,
      contextType: contextType,
      contextId: contextId,
      contextStatus: contextStatus,
      contextSnapshot: contextSnapshot,
      context: context,
      group: group ?? this.group,
      peer: peer ?? this.peer,
      peerPhone: peerPhone,
      presence: presence ?? this.presence,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessage: lastMessage ?? this.lastMessage,
      state: state ?? this.state,
    );
  }

  SocialChatThread resolvedWithPeerFallback(SocialAuthor? fallbackPeer) {
    if (isGroup || fallbackPeer == null) return this;
    return copyWith(peer: peer.mergedWith(fallbackPeer));
  }
}

class SocialRelationRequest {
  final SocialRelation relation;
  final SocialAuthor user;
  final DateTime? requestedAt;

  const SocialRelationRequest({
    required this.relation,
    required this.user,
    required this.requestedAt,
  });

  factory SocialRelationRequest.fromJson(Map<String, dynamic> j) =>
      SocialRelationRequest(
        relation: SocialRelation.fromJson(
          Map<String, dynamic>.from(j['relation'] as Map? ?? const {}),
        ),
        user: SocialAuthor.fromJson(
          Map<String, dynamic>.from(j['user'] as Map? ?? const {}),
        ),
        requestedAt: parseNullableDateTime(
          j['requestedAt'] ?? j['requested_at'],
        ),
      );
}

class SocialCallSession {
  final int id;
  final int threadId;
  final int callerUserId;
  final int calleeUserId;
  final String status;
  final bool isCaller;
  final bool isCallee;
  final DateTime? startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final String? endReason;

  const SocialCallSession({
    required this.id,
    required this.threadId,
    required this.callerUserId,
    required this.calleeUserId,
    required this.status,
    required this.isCaller,
    required this.isCallee,
    required this.startedAt,
    required this.answeredAt,
    required this.endedAt,
    required this.endReason,
  });

  factory SocialCallSession.fromJson(Map<String, dynamic> j) =>
      SocialCallSession(
        id: parseInt(j['id']),
        threadId: parseInt(j['threadId'] ?? j['thread_id']),
        callerUserId: parseInt(j['callerUserId'] ?? j['caller_user_id']),
        calleeUserId: parseInt(j['calleeUserId'] ?? j['callee_user_id']),
        status: parseString(j['status'], fallback: 'ringing'),
        isCaller: parseBool(j['isCaller'] ?? j['is_caller']),
        isCallee: parseBool(j['isCallee'] ?? j['is_callee']),
        startedAt: parseNullableDateTime(j['startedAt'] ?? j['started_at']),
        answeredAt: parseNullableDateTime(j['answeredAt'] ?? j['answered_at']),
        endedAt: parseNullableDateTime(j['endedAt'] ?? j['ended_at']),
        endReason: parseNullableString(j['endReason'] ?? j['end_reason']),
      );
}

class SocialCallSignal {
  final int id;
  final int sessionId;
  final int threadId;
  final int senderUserId;
  final String signalType;
  final Map<String, dynamic> signalPayload;
  final DateTime? createdAt;

  const SocialCallSignal({
    required this.id,
    required this.sessionId,
    required this.threadId,
    required this.senderUserId,
    required this.signalType,
    required this.signalPayload,
    required this.createdAt,
  });

  factory SocialCallSignal.fromJson(Map<String, dynamic> j) => SocialCallSignal(
    id: parseInt(j['id']),
    sessionId: parseInt(j['sessionId'] ?? j['session_id']),
    threadId: parseInt(j['threadId'] ?? j['thread_id']),
    senderUserId: parseInt(j['senderUserId'] ?? j['sender_user_id']),
    signalType: parseString(
      j['signalType'] ?? j['signal_type'],
      fallback: 'ice',
    ),
    signalPayload: Map<String, dynamic>.from(
      j['signalPayload'] ?? j['signal_payload'] ?? const {},
    ),
    createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
  );
}

class SocialExplorePayload {
  final List<SocialPost> forYou;
  final List<SocialPost> reels;
  final List<SocialPost> trendingBasmaya;
  final List<SocialPost> sameArea;
  final List<SocialPost> restaurantReviews;
  final List<SocialPost> popularPosts;
  final List<String> localTopics;
  final List<SocialUserSearchResult> suggestedPeople;
  final DateTime? generatedAt;

  const SocialExplorePayload({
    required this.forYou,
    required this.reels,
    required this.trendingBasmaya,
    required this.sameArea,
    required this.restaurantReviews,
    required this.popularPosts,
    required this.localTopics,
    required this.suggestedPeople,
    required this.generatedAt,
  });

  factory SocialExplorePayload.fromJson(
    Map<String, dynamic> j,
  ) => SocialExplorePayload(
    forYou: List<dynamic>.from(j['forYou'] ?? j['for_you'] ?? const [])
        .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false),
    reels: List<dynamic>.from(j['reels'] as List? ?? const [])
        .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false),
    trendingBasmaya:
        List<dynamic>.from(
              j['trendingBasmaya'] ?? j['trending_basmaya'] ?? const [],
            )
            .map(
              (e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(growable: false),
    sameArea: List<dynamic>.from(j['sameArea'] ?? j['same_area'] ?? const [])
        .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false),
    restaurantReviews:
        List<dynamic>.from(
              j['restaurantReviews'] ?? j['restaurant_reviews'] ?? const [],
            )
            .map(
              (e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(growable: false),
    popularPosts:
        List<dynamic>.from(j['popularPosts'] ?? j['popular_posts'] ?? const [])
            .map(
              (e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(growable: false),
    localTopics:
        List<dynamic>.from(j['localTopics'] ?? j['local_topics'] ?? const [])
            .map((e) => '$e')
            .where((e) => e.trim().isNotEmpty)
            .toList(growable: false),
    suggestedPeople:
        List<dynamic>.from(
              j['suggestedPeople'] ?? j['suggested_people'] ?? const [],
            )
            .map(
              (e) => SocialUserSearchResult.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(growable: false),
    generatedAt: parseNullableDateTime(j['generatedAt'] ?? j['generated_at']),
  );
}

class SocialHashtag {
  final int id;
  final String tag;
  final String normalizedTag;
  final int usageCount;
  final DateTime? lastUsedAt;

  const SocialHashtag({
    required this.id,
    required this.tag,
    required this.normalizedTag,
    required this.usageCount,
    required this.lastUsedAt,
  });

  factory SocialHashtag.fromJson(Map<String, dynamic> j) => SocialHashtag(
    id: parseInt(j['id']),
    tag: parseString(j['tag']),
    normalizedTag: parseString(
      j['normalizedTag'] ?? j['normalized_tag'],
      fallback: parseString(j['tag']),
    ),
    usageCount: parseInt(j['usageCount'] ?? j['usage_count']),
    lastUsedAt: parseNullableDateTime(j['lastUsedAt'] ?? j['last_used_at']),
  );
}

class SocialProfileInsights {
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> bestPostingTimes;
  final List<Map<String, dynamic>> audienceLocality;
  final List<SocialPost> topContent;

  const SocialProfileInsights({
    required this.summary,
    required this.bestPostingTimes,
    required this.audienceLocality,
    required this.topContent,
  });

  factory SocialProfileInsights.fromJson(
    Map<String, dynamic> j,
  ) => SocialProfileInsights(
    summary: Map<String, dynamic>.from(j['summary'] as Map? ?? const {}),
    bestPostingTimes: List<dynamic>.from(
      j['bestPostingTimes'] ?? j['best_posting_times'] ?? const [],
    ).map((e) => Map<String, dynamic>.from(e as Map)).toList(growable: false),
    audienceLocality: List<dynamic>.from(
      j['audienceLocality'] ?? j['audience_locality'] ?? const [],
    ).map((e) => Map<String, dynamic>.from(e as Map)).toList(growable: false),
    topContent:
        List<dynamic>.from(j['topContent'] ?? j['top_content'] ?? const [])
            .map(
              (e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(growable: false),
  );
}

class SocialReelMetrics {
  final int impressionsCount;
  final int viewsCount;
  final int averageWatchDurationMs;
  final double averageCompletionRate;
  final int replayCount;

  const SocialReelMetrics({
    required this.impressionsCount,
    required this.viewsCount,
    required this.averageWatchDurationMs,
    required this.averageCompletionRate,
    required this.replayCount,
  });

  factory SocialReelMetrics.fromJson(
    Map<String, dynamic> j,
  ) => SocialReelMetrics(
    impressionsCount: parseInt(j['impressionsCount'] ?? j['impressions_count']),
    viewsCount: parseInt(j['viewsCount'] ?? j['views_count']),
    averageWatchDurationMs: parseInt(
      j['averageWatchDurationMs'] ?? j['average_watch_duration_ms'],
    ),
    averageCompletionRate:
        double.tryParse(
          '${j['averageCompletionRate'] ?? j['average_completion_rate'] ?? 0}',
        ) ??
        0,
    replayCount: parseInt(j['replayCount'] ?? j['replay_count']),
  );
}

class SocialReelItem {
  final SocialPost post;
  final SocialReelMetrics metrics;

  const SocialReelItem({required this.post, required this.metrics});

  factory SocialReelItem.fromJson(Map<String, dynamic> j) => SocialReelItem(
    post: SocialPost.fromJson(
      Map<String, dynamic>.from(j['post'] as Map? ?? j),
    ),
    metrics: SocialReelMetrics.fromJson(
      Map<String, dynamic>.from(j['metrics'] as Map? ?? const {}),
    ),
  );
}

class SocialSavedCollection {
  final int id;
  final int userId;
  final String title;
  final String? description;
  final String? systemKey;
  final int itemsCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SocialSavedCollection({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.systemKey,
    required this.itemsCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SocialSavedCollection.fromJson(Map<String, dynamic> j) =>
      SocialSavedCollection(
        id: parseInt(j['id']),
        userId: parseInt(j['userId'] ?? j['user_id']),
        title: parseString(j['title']),
        description: parseNullableString(j['description']),
        systemKey: parseNullableString(j['systemKey'] ?? j['system_key']),
        itemsCount: parseInt(j['itemsCount'] ?? j['items_count']),
        createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
        updatedAt: parseNullableDateTime(j['updatedAt'] ?? j['updated_at']),
      );
}

class SocialSavedItem {
  final int id;
  final String entityType;
  final int entityId;
  final int? collectionId;
  final SocialPost content;
  final DateTime? createdAt;

  const SocialSavedItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.collectionId,
    required this.content,
    required this.createdAt,
  });

  factory SocialSavedItem.fromJson(Map<String, dynamic> j) => SocialSavedItem(
    id: parseInt(j['id']),
    entityType: parseString(
      j['entityType'] ?? j['entity_type'],
      fallback: 'post',
    ),
    entityId: parseInt(j['entityId'] ?? j['entity_id']),
    collectionId: parseNullableInt(j['collectionId'] ?? j['collection_id']),
    content: SocialPost.fromJson(
      Map<String, dynamic>.from(j['content'] as Map? ?? const {}),
    ),
    createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
  );
}

class SocialUserSearchResult {
  final SocialAuthor user;
  final SocialRelation relation;

  const SocialUserSearchResult({required this.user, required this.relation});

  factory SocialUserSearchResult.fromJson(Map<String, dynamic> j) =>
      SocialUserSearchResult(
        user: SocialAuthor.fromJson(
          Map<String, dynamic>.from(
            j['user'] as Map? ??
                <String, dynamic>{
                  'id': j['id'],
                  'username': j['username'],
                  'fullName': j['fullName'] ?? j['full_name'],
                  'imageUrl': j['imageUrl'] ?? j['image_url'],
                  'phone': j['phone'],
                  'role': j['role'],
                  'badges': j['badges'],
                  'isPremiumCreator':
                      j['isPremiumCreator'] ?? j['is_premium_creator'],
                  'isResidentVerified':
                      j['isResidentVerified'] ?? j['is_resident_verified'],
                  'isMerchantVerified':
                      j['isMerchantVerified'] ?? j['is_merchant_verified'],
                },
          ),
        ),
        relation: SocialRelation.fromJson(
          Map<String, dynamic>.from(j['relation'] as Map? ?? const {}),
        ),
      );
}

class SocialSearchResults {
  final List<Map<String, dynamic>> recentSearches;
  final List<SocialUserSearchResult> suggestedPeople;
  final List<SocialUserSearchResult> users;
  final List<SocialHashtag> hashtags;
  final List<SocialPost> posts;
  final List<SocialPost> reels;
  final List<SocialPost> reviews;
  final List<SocialMerchantOption> merchants;

  const SocialSearchResults({
    required this.recentSearches,
    required this.suggestedPeople,
    required this.users,
    required this.hashtags,
    required this.posts,
    required this.reels,
    required this.reviews,
    required this.merchants,
  });

  factory SocialSearchResults.fromJson(Map<String, dynamic> j) {
    final results = Map<String, dynamic>.from(
      j['results'] as Map? ?? const <String, dynamic>{},
    );
    List<dynamic> readList(String camelKey, String snakeKey) {
      final nested = results[camelKey] ?? results[snakeKey];
      if (nested is List) return List<dynamic>.from(nested);
      final root = j[camelKey] ?? j[snakeKey];
      return root is List ? List<dynamic>.from(root) : const <dynamic>[];
    }

    return SocialSearchResults(
      recentSearches: List<dynamic>.from(
        j['recentSearches'] ?? j['recent_searches'] ?? const [],
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList(growable: false),
      suggestedPeople: readList('suggestedPeople', 'suggested_people')
          .map(
            (e) => SocialUserSearchResult.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false),
      users: readList('users', 'users')
          .map(
            (e) => SocialUserSearchResult.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false),
      hashtags: readList('hashtags', 'hashtags')
          .map(
            (e) => SocialHashtag.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false),
      posts: readList('posts', 'posts')
          .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
      reels: readList('reels', 'reels')
          .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
      reviews: readList('reviews', 'reviews')
          .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
      merchants: readList('merchants', 'merchants')
          .map(
            (e) => SocialMerchantOption.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class SocialCapabilityRestrictionItem {
  final int id;
  final int userId;
  final String capabilityKey;
  final String? reason;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? createdAt;
  final DateTime? revokedAt;

  const SocialCapabilityRestrictionItem({
    required this.id,
    required this.userId,
    required this.capabilityKey,
    required this.reason,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    required this.revokedAt,
  });

  factory SocialCapabilityRestrictionItem.fromJson(Map<String, dynamic> j) =>
      SocialCapabilityRestrictionItem(
        id: parseInt(j['id']),
        userId: parseInt(j['userId'] ?? j['user_id']),
        capabilityKey: parseString(
          j['capabilityKey'] ?? j['capability_key'],
        ).toLowerCase(),
        reason: parseNullableString(j['reason']),
        startsAt: parseNullableDateTime(j['startsAt'] ?? j['starts_at']),
        endsAt: parseNullableDateTime(j['endsAt'] ?? j['ends_at']),
        createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
        revokedAt: parseNullableDateTime(j['revokedAt'] ?? j['revoked_at']),
      );
}

class SocialChatMonitorThread {
  final int id;
  final String kind;
  final String monitorKey;
  final int? threadId;
  final String? scopeType;
  final String? scopeCode;
  final String? scopeTitle;
  final String? scopeSubtitle;
  final String participantLabel;
  final List<SocialAuthor> participants;
  final int participantCount;
  final DateTime? lastMessageAt;
  final SocialChatMessage? lastMessage;

  const SocialChatMonitorThread({
    required this.id,
    required this.kind,
    required this.monitorKey,
    required this.threadId,
    required this.scopeType,
    required this.scopeCode,
    required this.scopeTitle,
    required this.scopeSubtitle,
    required this.participantLabel,
    required this.participants,
    required this.participantCount,
    required this.lastMessageAt,
    required this.lastMessage,
  });

  bool get isCommunity => kind == 'community';
  bool get isDirect => kind == 'direct';

  factory SocialChatMonitorThread.fromJson(Map<String, dynamic> j) {
    final participantRows = List<dynamic>.from(
      j['participants'] as List? ?? const [],
    );
    return SocialChatMonitorThread(
      id: parseInt(j['id'] ?? j['threadId'] ?? j['thread_id'], fallback: 0),
      kind: parseString(j['kind'], fallback: 'direct'),
      monitorKey: parseString(
        j['monitorKey'] ?? j['monitor_key'],
        fallback: 'direct',
      ),
      threadId: parseNullableInt(j['threadId'] ?? j['thread_id'] ?? j['id']),
      scopeType: parseNullableString(j['scopeType'] ?? j['scope_type']),
      scopeCode: parseNullableString(j['scopeCode'] ?? j['scope_code']),
      scopeTitle: parseNullableString(j['scopeTitle'] ?? j['scope_title']),
      scopeSubtitle: parseNullableString(
        j['scopeSubtitle'] ?? j['scope_subtitle'],
      ),
      participantLabel: parseString(
        j['participantLabel'] ?? j['participant_label'],
      ),
      participants: participantRows
          .map(
            (e) => SocialAuthor.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false),
      participantCount: parseInt(
        j['participantCount'] ?? j['participant_count'],
      ),
      lastMessageAt: parseNullableDateTime(
        j['lastMessageAt'] ?? j['last_message_at'],
      ),
      lastMessage: j['lastMessage'] is Map
          ? SocialChatMessage.fromJson(
              Map<String, dynamic>.from(j['lastMessage'] as Map),
            )
          : null,
    );
  }
}

class SocialCommunityChatMessage {
  final int id;
  final String? scopeType;
  final String? scopeCode;
  final int senderUserId;
  final String body;
  final String? clientMessageId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final bool isDeleted;
  final bool isMine;
  final bool isSystem;
  final Map<String, int> reactionCounts;
  final int reactionTotalCount;
  final String? myReaction;
  final SocialChatReplyPreview? replyToMessage;
  final SocialChatAttachment? attachment;
  final SocialSharedEntity? sharedEntity;
  final SocialAuthor sender;

  const SocialCommunityChatMessage({
    required this.id,
    required this.scopeType,
    required this.scopeCode,
    required this.senderUserId,
    required this.body,
    this.clientMessageId,
    required this.createdAt,
    required this.updatedAt,
    required this.editedAt,
    required this.deletedAt,
    required this.isDeleted,
    required this.isMine,
    required this.isSystem,
    required this.reactionCounts,
    required this.reactionTotalCount,
    required this.myReaction,
    required this.replyToMessage,
    required this.attachment,
    required this.sharedEntity,
    required this.sender,
  });

  factory SocialCommunityChatMessage.fromJson(
    Map<String, dynamic> j,
  ) => SocialCommunityChatMessage(
    id: parseInt(j['id']),
    scopeType: parseNullableString(j['scopeType'] ?? j['scope_type']),
    scopeCode: parseNullableString(j['scopeCode'] ?? j['scope_code']),
    senderUserId: parseInt(j['senderUserId'] ?? j['sender_user_id']),
    body: parseString(j['body']),
    clientMessageId: parseNullableString(
      j['clientMessageId'] ?? j['client_message_id'],
    ),
    createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
    updatedAt: parseNullableDateTime(j['updatedAt'] ?? j['updated_at']),
    editedAt: parseNullableDateTime(j['editedAt'] ?? j['edited_at']),
    deletedAt: parseNullableDateTime(j['deletedAt'] ?? j['deleted_at']),
    isDeleted: parseBool(j['isDeleted'] ?? j['is_deleted']),
    isMine: parseBool(j['isMine'] ?? j['is_mine']),
    isSystem: parseBool(j['isSystem'] ?? j['is_system']),
    reactionCounts: _parseReactionCounts(j['reactions']),
    reactionTotalCount: parseInt(
      j['reactionTotalCount'] ?? j['reaction_total_count'],
    ),
    myReaction: parseNullableString(j['myReaction'] ?? j['my_reaction']),
    replyToMessage: j['replyToMessage'] is Map || j['reply_to_message'] is Map
        ? SocialChatReplyPreview.fromJson(
            Map<String, dynamic>.from(
              (j['replyToMessage'] ?? j['reply_to_message']) as Map,
            ),
          )
        : null,
    attachment:
        j['attachment'] is Map ||
            j['attachmentUrl'] != null ||
            j['attachment_url'] != null
        ? SocialChatAttachment.fromJson(
            Map<String, dynamic>.from(
              j['attachment'] as Map? ??
                  <String, dynamic>{
                    'attachmentUrl': j['attachmentUrl'] ?? j['attachment_url'],
                    'attachmentKind':
                        j['attachmentKind'] ?? j['attachment_kind'],
                    'attachmentName':
                        j['attachmentName'] ?? j['attachment_name'],
                    'attachmentMimeType':
                        j['attachmentMimeType'] ?? j['attachment_mime_type'],
                    'sizeBytes': j['sizeBytes'] ?? j['attachment_size_bytes'],
                    'attachmentDurationMs':
                        j['attachmentDurationMs'] ??
                        j['attachment_duration_ms'],
                  },
            ),
          )
        : null,
    sharedEntity:
        j['sharedEntity'] is Map ||
            j['shared_entity'] is Map ||
            j['sharedEntityType'] != null ||
            j['shared_entity_type'] != null
        ? SocialSharedEntity.fromJson(
            Map<String, dynamic>.from(
              (j['sharedEntity'] ?? j['shared_entity']) as Map? ??
                  <String, dynamic>{
                    'type':
                        j['sharedEntityType'] ??
                        j['shared_entity_type'] ??
                        'post',
                    'id': j['sharedEntityId'] ?? j['shared_entity_id'],
                    'snapshot':
                        j['sharedSnapshot'] ??
                        j['shared_snapshot_json'] ??
                        j['shared_snapshot'],
                  },
            ),
          )
        : null,
    sender: SocialAuthor.fromJson(
      Map<String, dynamic>.from(j['sender'] as Map? ?? const {}),
    ),
  );
}

class SocialCommunityAnnouncement {
  final int id;
  final String title;
  final String body;
  final DateTime? createdAt;

  const SocialCommunityAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory SocialCommunityAnnouncement.fromJson(Map<String, dynamic> j) =>
      SocialCommunityAnnouncement(
        id: parseInt(j['id']),
        title: parseString(j['title']),
        body: parseString(j['body']),
        createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
      );
}

class SocialCommunityBill {
  final int id;
  final String title;
  final String? category;
  final num? amount;
  final String? apartmentCode;
  final String? dueDate;
  final String? description;
  final String? details;
  final SocialChatAttachment? attachment;

  const SocialCommunityBill({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.apartmentCode,
    required this.dueDate,
    required this.description,
    required this.details,
    required this.attachment,
  });

  factory SocialCommunityBill.fromJson(Map<String, dynamic> j) =>
      SocialCommunityBill(
        id: parseInt(j['id']),
        title: parseString(j['title'], fallback: 'Bill'),
        category: parseNullableString(j['category']),
        amount: num.tryParse('${j['amount'] ?? ''}'),
        apartmentCode: parseNullableString(
          j['apartmentCode'] ?? j['apartment_code'],
        ),
        dueDate: parseNullableString(j['dueDate'] ?? j['due_date']),
        description: parseNullableString(j['description']),
        details: parseNullableString(j['details']),
        attachment:
            (j['attachment'] is Map ||
                j['attachmentUrl'] != null ||
                j['attachment_url'] != null)
            ? SocialChatAttachment.fromJson(
                Map<String, dynamic>.from(
                  j['attachment'] as Map? ??
                      <String, dynamic>{
                        'attachmentUrl':
                            j['attachmentUrl'] ?? j['attachment_url'],
                        'attachmentKind':
                            j['attachmentKind'] ?? j['attachment_kind'],
                        'attachmentName':
                            j['attachmentName'] ?? j['attachment_name'],
                      },
                ),
              )
            : null,
      );
}

class SocialCommunityManager {
  final int managerUserId;
  final SocialAuthor manager;

  const SocialCommunityManager({
    required this.managerUserId,
    required this.manager,
  });

  factory SocialCommunityManager.fromJson(Map<String, dynamic> j) =>
      SocialCommunityManager(
        managerUserId: parseInt(j['managerUserId'] ?? j['manager_user_id']),
        manager: SocialAuthor.fromJson(
          Map<String, dynamic>.from(j['manager'] as Map? ?? const {}),
        ),
      );
}

class SocialCommunityManagerCandidate {
  final SocialAuthor user;
  final bool isManager;

  const SocialCommunityManagerCandidate({
    required this.user,
    required this.isManager,
  });

  factory SocialCommunityManagerCandidate.fromJson(Map<String, dynamic> j) =>
      SocialCommunityManagerCandidate(
        user: SocialAuthor.fromJson(
          Map<String, dynamic>.from(j['user'] as Map? ?? j),
        ),
        isManager: parseBool(j['isManager'] ?? j['is_manager']),
      );
}

class SocialCommunityChatMemberCandidate {
  final SocialAuthor user;
  final bool isChatRestricted;
  final bool isScopeRemoved;
  final bool isManager;

  const SocialCommunityChatMemberCandidate({
    required this.user,
    required this.isChatRestricted,
    required this.isScopeRemoved,
    required this.isManager,
  });

  factory SocialCommunityChatMemberCandidate.fromJson(Map<String, dynamic> j) =>
      SocialCommunityChatMemberCandidate(
        user: SocialAuthor.fromJson(
          Map<String, dynamic>.from(j['user'] as Map? ?? j),
        ),
        isChatRestricted: parseBool(
          j['isChatRestricted'] ?? j['is_chat_restricted'],
        ),
        isScopeRemoved: parseBool(j['isScopeRemoved'] ?? j['is_scope_removed']),
        isManager: parseBool(j['isManager'] ?? j['is_manager']),
      );
}

class SocialCommunityScopeInfo {
  final String scopeType;
  final String scopeCode;

  const SocialCommunityScopeInfo({
    required this.scopeType,
    required this.scopeCode,
  });

  factory SocialCommunityScopeInfo.fromJson(Map<String, dynamic> j) =>
      SocialCommunityScopeInfo(
        scopeType: parseString(j['scopeType'] ?? j['scope_type']),
        scopeCode: parseString(j['scopeCode'] ?? j['scope_code']),
      );
}

Map<String, int> _parseReactionCounts(dynamic raw) {
  if (raw is! Map) return const <String, int>{};
  final countsRaw = raw['counts'];
  if (countsRaw is! Map) return const <String, int>{};

  final out = <String, int>{};
  for (final entry in countsRaw.entries) {
    final key = '${entry.key}'.trim().toLowerCase();
    if (key.isEmpty) continue;
    final value = int.tryParse('${entry.value}') ?? 0;
    if (value <= 0) continue;
    out[key] = value;
  }
  return out;
}

int _parseReactionTotalCount(dynamic raw) {
  if (raw is! Map) return 0;
  final direct = int.tryParse(
    '${raw['totalCount'] ?? raw['total_count'] ?? ''}',
  );
  if (direct != null && direct >= 0) return direct;
  final counts = _parseReactionCounts(raw);
  return counts.values.fold<int>(0, (sum, item) => sum + item);
}

String? _parseMyReaction(dynamic raw) {
  if (raw is! Map) return null;
  final value = raw['myReaction'] ?? raw['my_reaction'];
  final text = '$value'.trim().toLowerCase();
  return text.isEmpty ? null : text;
}
