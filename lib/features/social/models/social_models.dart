import '../../../core/utils/parsers.dart';

class SocialAuthor {
  final int id;
  final String fullName;
  final String? imageUrl;
  final String? phone;
  final String role;

  const SocialAuthor({
    required this.id,
    required this.fullName,
    required this.imageUrl,
    required this.phone,
    required this.role,
  });

  factory SocialAuthor.fromJson(Map<String, dynamic> j) => SocialAuthor(
    id: parseInt(j['id']),
    fullName: parseString(j['fullName'] ?? j['full_name']),
    imageUrl: parseNullableString(j['imageUrl'] ?? j['image_url']),
    phone: parseNullableString(j['phone']),
    role: parseString(j['role'], fallback: 'user'),
  );
}

class SocialPost {
  final int id;
  final int userId;
  final String postKind;
  final String caption;
  final String? mediaUrl;
  final String? mediaKind;
  final int? merchantId;
  final String? merchantName;
  final int? reviewRating;
  final int likesCount;
  final int commentsCount;
  final bool isLiked;
  final DateTime? createdAt;
  final SocialAuthor author;

  const SocialPost({
    required this.id,
    required this.userId,
    required this.postKind,
    required this.caption,
    required this.mediaUrl,
    required this.mediaKind,
    required this.merchantId,
    required this.merchantName,
    required this.reviewRating,
    required this.likesCount,
    required this.commentsCount,
    required this.isLiked,
    required this.createdAt,
    required this.author,
  });

  factory SocialPost.fromJson(Map<String, dynamic> j) => SocialPost(
    id: parseInt(j['id']),
    userId: parseInt(j['userId'] ?? j['user_id']),
    postKind: parseString(j['postKind'] ?? j['post_kind'], fallback: 'text'),
    caption: parseString(j['caption']),
    mediaUrl: parseNullableString(j['mediaUrl'] ?? j['media_url']),
    mediaKind: parseNullableString(j['mediaKind'] ?? j['media_kind']),
    merchantId: j['merchantId'] == null && j['merchant_id'] == null
        ? null
        : parseInt(j['merchantId'] ?? j['merchant_id']),
    merchantName: parseNullableString(j['merchantName'] ?? j['merchant_name']),
    reviewRating: j['reviewRating'] == null && j['review_rating'] == null
        ? null
        : parseInt(j['reviewRating'] ?? j['review_rating']),
    likesCount: parseInt(j['likesCount'] ?? j['likes_count']),
    commentsCount: parseInt(j['commentsCount'] ?? j['comments_count']),
    isLiked: parseBool(j['isLiked'] ?? j['is_liked']),
    createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
    author: SocialAuthor.fromJson(
      Map<String, dynamic>.from(j['author'] as Map? ?? const {}),
    ),
  );

  SocialPost copyWith({int? likesCount, int? commentsCount, bool? isLiked}) {
    return SocialPost(
      id: id,
      userId: userId,
      postKind: postKind,
      caption: caption,
      mediaUrl: mediaUrl,
      mediaKind: mediaKind,
      merchantId: merchantId,
      merchantName: merchantName,
      reviewRating: reviewRating,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      isLiked: isLiked ?? this.isLiked,
      createdAt: createdAt,
      author: author,
    );
  }
}

class SocialComment {
  final int id;
  final int postId;
  final int userId;
  final String body;
  final DateTime? createdAt;
  final SocialAuthor author;

  const SocialComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.body,
    required this.createdAt,
    required this.author,
  });

  factory SocialComment.fromJson(Map<String, dynamic> j) => SocialComment(
    id: parseInt(j['id']),
    postId: parseInt(j['postId'] ?? j['post_id']),
    userId: parseInt(j['userId'] ?? j['user_id']),
    body: parseString(j['body']),
    createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
    author: SocialAuthor.fromJson(
      Map<String, dynamic>.from(j['author'] as Map? ?? const {}),
    ),
  );
}

class SocialMerchantOption {
  final int id;
  final String name;
  final String type;
  final String phone;
  final String? imageUrl;

  const SocialMerchantOption({
    required this.id,
    required this.name,
    required this.type,
    required this.phone,
    required this.imageUrl,
  });

  factory SocialMerchantOption.fromJson(Map<String, dynamic> j) =>
      SocialMerchantOption(
        id: parseInt(j['id']),
        name: parseString(j['name']),
        type: parseString(j['type'], fallback: 'market'),
        phone: parseString(j['phone']),
        imageUrl: parseNullableString(j['imageUrl'] ?? j['image_url']),
      );
}

class SocialStory {
  final int id;
  final int userId;
  final String caption;
  final String? mediaUrl;
  final String? mediaKind;
  final SocialStoryStyle style;
  final bool isViewed;
  final bool isMine;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const SocialStory({
    required this.id,
    required this.userId,
    required this.caption,
    required this.mediaUrl,
    required this.mediaKind,
    required this.style,
    required this.isViewed,
    required this.isMine,
    required this.createdAt,
    required this.expiresAt,
  });

  factory SocialStory.fromJson(Map<String, dynamic> j) => SocialStory(
    id: parseInt(j['id']),
    userId: parseInt(j['userId'] ?? j['user_id']),
    caption: parseString(j['caption']),
    mediaUrl: parseNullableString(j['mediaUrl'] ?? j['media_url']),
    mediaKind: parseNullableString(j['mediaKind'] ?? j['media_kind']),
    style: SocialStoryStyle.fromJson(
      Map<String, dynamic>.from(
        j['storyStyle'] ?? j['story_style'] ?? const <String, dynamic>{},
      ),
    ),
    isViewed: parseBool(j['isViewed'] ?? j['is_viewed']),
    isMine: parseBool(j['isMine'] ?? j['is_mine']),
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

  const SocialStoryStyle({
    required this.backgroundColor,
    required this.textColor,
    required this.textAlign,
    required this.fontFamily,
    required this.fontWeight,
    required this.fontScale,
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
  );

  Map<String, dynamic> toJson() => {
    'backgroundColor': backgroundColor,
    'textColor': textColor,
    'textAlign': textAlign,
    'fontFamily': fontFamily,
    'fontWeight': fontWeight,
    'fontScale': fontScale,
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
  final int commentsReceived;
  final int activeStories;
  final int highlightsCount;

  const SocialUserPostStats({
    required this.totalPosts,
    required this.imagePosts,
    required this.videoPosts,
    required this.reviewPosts,
    required this.likesReceived,
    required this.commentsReceived,
    required this.activeStories,
    required this.highlightsCount,
  });

  factory SocialUserPostStats.fromJson(
    Map<String, dynamic> j,
  ) => SocialUserPostStats(
    totalPosts: parseInt(j['totalPosts'] ?? j['total_posts']),
    imagePosts: parseInt(j['imagePosts'] ?? j['image_posts']),
    videoPosts: parseInt(j['videoPosts'] ?? j['video_posts']),
    reviewPosts: parseInt(j['reviewPosts'] ?? j['review_posts']),
    likesReceived: parseInt(j['likesReceived'] ?? j['likes_received']),
    commentsReceived: parseInt(j['commentsReceived'] ?? j['comments_received']),
    activeStories: parseInt(j['activeStories'] ?? j['active_stories']),
    highlightsCount: parseInt(j['highlightsCount'] ?? j['highlights_count']),
  );
}

class SocialUserProfile {
  final int id;
  final String fullName;
  final String role;
  final String bio;
  final String? imageUrl;
  final String? phone;
  final bool showPhone;
  final bool postsPublic;
  final bool storiesPublic;
  final DateTime? joinedAt;
  final bool isMe;
  final SocialUserPostStats stats;

  const SocialUserProfile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.bio,
    required this.imageUrl,
    required this.phone,
    required this.showPhone,
    required this.postsPublic,
    required this.storiesPublic,
    required this.joinedAt,
    required this.isMe,
    required this.stats,
  });

  factory SocialUserProfile.fromJson(Map<String, dynamic> j) {
    final privacy = Map<String, dynamic>.from(
      j['privacy'] as Map? ?? const <String, dynamic>{},
    );
    return SocialUserProfile(
      id: parseInt(j['id']),
      fullName: parseString(j['fullName'] ?? j['full_name']),
      role: parseString(j['role'], fallback: 'user'),
      bio: parseString(j['bio'], fallback: ''),
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
      joinedAt: parseNullableDateTime(j['joinedAt'] ?? j['joined_at']),
      isMe: parseBool(j['isMe'] ?? j['is_me']),
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

class SocialChatMessage {
  final int id;
  final int threadId;
  final int senderUserId;
  final String body;
  final DateTime? createdAt;
  final bool isMine;
  final SocialAuthor sender;

  const SocialChatMessage({
    required this.id,
    required this.threadId,
    required this.senderUserId,
    required this.body,
    required this.createdAt,
    required this.isMine,
    required this.sender,
  });

  factory SocialChatMessage.fromJson(Map<String, dynamic> j) =>
      SocialChatMessage(
        id: parseInt(j['id']),
        threadId: parseInt(j['threadId'] ?? j['thread_id']),
        senderUserId: parseInt(j['senderUserId'] ?? j['sender_user_id']),
        body: parseString(j['body']),
        createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
        isMine: parseBool(j['isMine'] ?? j['is_mine']),
        sender: SocialAuthor.fromJson(
          Map<String, dynamic>.from(j['sender'] as Map? ?? const {}),
        ),
      );
}

class SocialChatThread {
  final int id;
  final SocialAuthor peer;
  final String peerPhone;
  final DateTime? lastMessageAt;
  final SocialChatMessage? lastMessage;

  const SocialChatThread({
    required this.id,
    required this.peer,
    required this.peerPhone,
    required this.lastMessageAt,
    required this.lastMessage,
  });

  factory SocialChatThread.fromJson(Map<String, dynamic> j) => SocialChatThread(
    id: parseInt(j['id']),
    peer: SocialAuthor.fromJson(
      Map<String, dynamic>.from(j['peer'] as Map? ?? const {}),
    ),
    peerPhone: parseString(
      j['peerPhone'] ??
          j['peer_phone'] ??
          (j['peer'] is Map ? (j['peer'] as Map)['phone'] : null),
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
