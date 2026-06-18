import '../core/local_media_file.dart';
import '../core/parsers.dart';
import 'social_models.dart';

enum SocialStoryComposerMode { text, media, reelShare, postShare }

enum SocialStoryBackgroundType { solid, gradient, posterBlur }

enum SocialStoryLayerType { text, mention, sticker, draw, reelShare, postShare }

class SocialStoryBackground {
  final SocialStoryBackgroundType type;
  final String primaryColor;
  final String? secondaryColor;
  final String? imageUrl;

  const SocialStoryBackground({
    required this.type,
    required this.primaryColor,
    required this.secondaryColor,
    required this.imageUrl,
  });

  factory SocialStoryBackground.fromJson(Map<String, dynamic> json) {
    final rawType = parseString(json['type'], fallback: 'solid');
    return SocialStoryBackground(
      type: SocialStoryBackgroundType.values.firstWhere(
        (value) => value.name == rawType,
        orElse: () => SocialStoryBackgroundType.solid,
      ),
      primaryColor: parseString(
        json['primaryColor'] ?? json['primary_color'],
        fallback: '#1E3A8A',
      ),
      secondaryColor: parseNullableString(
        json['secondaryColor'] ?? json['secondary_color'],
      ),
      imageUrl: parseNullableString(json['imageUrl'] ?? json['image_url']),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'primaryColor': primaryColor,
    if (secondaryColor != null) 'secondaryColor': secondaryColor,
    if (imageUrl != null) 'imageUrl': imageUrl,
  };
}

class SocialStoryAttachment {
  final String type;
  final int? reelId;
  final int? postId;
  final String? authorName;
  final String? posterUrl;
  final String? caption;
  final String? mediaUrl;
  final String? mediaKind;
  final String? label;

  const SocialStoryAttachment({
    required this.type,
    required this.reelId,
    required this.postId,
    required this.authorName,
    required this.posterUrl,
    required this.caption,
    required this.mediaUrl,
    required this.mediaKind,
    required this.label,
  });

  factory SocialStoryAttachment.fromJson(Map<String, dynamic> json) {
    return SocialStoryAttachment(
      type: parseString(json['type']),
      reelId: parseNullableInt(json['reelId'] ?? json['reel_id']),
      postId: parseNullableInt(json['postId'] ?? json['post_id']),
      authorName: parseNullableString(
        json['authorName'] ?? json['author_name'],
      ),
      posterUrl: parseNullableString(json['posterUrl'] ?? json['poster_url']),
      caption: parseNullableString(json['caption']),
      mediaUrl: parseNullableString(json['mediaUrl'] ?? json['media_url']),
      mediaKind: parseNullableString(json['mediaKind'] ?? json['media_kind']),
      label: parseNullableString(json['label']),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    if (reelId != null) 'reelId': reelId,
    if (postId != null) 'postId': postId,
    if (authorName != null) 'authorName': authorName,
    if (posterUrl != null) 'posterUrl': posterUrl,
    if (caption != null) 'caption': caption,
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (mediaKind != null) 'mediaKind': mediaKind,
    if (label != null) 'label': label,
  };

  bool get isReelShare => type == 'reel_share';
  bool get isPostShare => type == 'post_share';
}

class SocialStoryPoint {
  final double x;
  final double y;

  const SocialStoryPoint({required this.x, required this.y});

  factory SocialStoryPoint.fromJson(Map<String, dynamic> json) =>
      SocialStoryPoint(
        x: double.tryParse('${json['x'] ?? 0}') ?? 0,
        y: double.tryParse('${json['y'] ?? 0}') ?? 0,
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

class SocialStoryDrawStroke {
  final String color;
  final double width;
  final List<SocialStoryPoint> points;

  const SocialStoryDrawStroke({
    required this.color,
    required this.width,
    required this.points,
  });

  factory SocialStoryDrawStroke.fromJson(
    Map<String, dynamic> json,
  ) => SocialStoryDrawStroke(
    color: parseString(json['color'], fallback: '#FFFFFF'),
    width: double.tryParse('${json['width'] ?? 4}') ?? 4,
    points: List<dynamic>.from(json['points'] as List? ?? const [])
        .map(
          (item) =>
              SocialStoryPoint.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'color': color,
    'width': width,
    'points': points.map((point) => point.toJson()).toList(growable: false),
  };
}

class SocialStoryLayer {
  final String id;
  final SocialStoryLayerType type;
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final int zIndex;
  final String? text;
  final String? color;
  final String? backgroundColor;
  final String? fontFamily;
  final String? fontWeight;
  final String? textAlign;
  final double? fontScale;
  final String? sticker;
  final int? mentionedUserId;
  final String? displayLabel;
  final List<SocialStoryDrawStroke> strokes;
  final bool locked;

  const SocialStoryLayer({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    required this.zIndex,
    required this.text,
    required this.color,
    required this.backgroundColor,
    required this.fontFamily,
    required this.fontWeight,
    required this.textAlign,
    required this.fontScale,
    required this.sticker,
    required this.mentionedUserId,
    required this.displayLabel,
    this.strokes = const <SocialStoryDrawStroke>[],
    this.locked = false,
  });

  factory SocialStoryLayer.fromJson(Map<String, dynamic> json) {
    final rawType = parseString(json['type'], fallback: 'text');
    return SocialStoryLayer(
      id: parseString(
        json['id'],
        fallback: DateTime.now().microsecondsSinceEpoch.toString(),
      ),
      type: SocialStoryLayerType.values.firstWhere(
        (value) => value.name == rawType,
        orElse: () => SocialStoryLayerType.text,
      ),
      x: double.tryParse('${json['x'] ?? 0.5}') ?? 0.5,
      y: double.tryParse('${json['y'] ?? 0.5}') ?? 0.5,
      scale: double.tryParse('${json['scale'] ?? 1.0}') ?? 1.0,
      rotation: double.tryParse('${json['rotation'] ?? 0.0}') ?? 0.0,
      zIndex: parseInt(json['zIndex'] ?? json['z_index'] ?? 0),
      text: parseNullableString(json['text']),
      color: parseNullableString(json['color']),
      backgroundColor: parseNullableString(
        json['backgroundColor'] ?? json['background_color'],
      ),
      fontFamily: parseNullableString(
        json['fontFamily'] ?? json['font_family'],
      ),
      fontWeight: parseNullableString(
        json['fontWeight'] ?? json['font_weight'],
      ),
      textAlign: parseNullableString(json['textAlign'] ?? json['text_align']),
      fontScale: (json['fontScale'] ?? json['font_scale']) == null
          ? null
          : double.tryParse('${json['fontScale'] ?? json['font_scale']}'),
      sticker: parseNullableString(json['sticker']),
      mentionedUserId: parseNullableInt(
        json['mentionedUserId'] ?? json['mentioned_user_id'],
      ),
      displayLabel: parseNullableString(
        json['displayLabel'] ?? json['display_label'],
      ),
      strokes: List<dynamic>.from(json['strokes'] as List? ?? const [])
          .map(
            (item) => SocialStoryDrawStroke.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      locked: parseBool(json['locked']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'x': x,
    'y': y,
    'scale': scale,
    'rotation': rotation,
    'zIndex': zIndex,
    if (text != null) 'text': text,
    if (color != null) 'color': color,
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
    if (fontFamily != null) 'fontFamily': fontFamily,
    if (fontWeight != null) 'fontWeight': fontWeight,
    if (textAlign != null) 'textAlign': textAlign,
    if (fontScale != null) 'fontScale': fontScale,
    if (sticker != null) 'sticker': sticker,
    if (mentionedUserId != null) 'mentionedUserId': mentionedUserId,
    if (displayLabel != null) 'displayLabel': displayLabel,
    if (strokes.isNotEmpty)
      'strokes': strokes
          .map((stroke) => stroke.toJson())
          .toList(growable: false),
    if (locked) 'locked': true,
  };

  SocialStoryLayer copyWith({
    double? x,
    double? y,
    double? scale,
    double? rotation,
    int? zIndex,
    String? text,
    String? color,
    String? backgroundColor,
    String? fontFamily,
    String? fontWeight,
    String? textAlign,
    double? fontScale,
    String? sticker,
    int? mentionedUserId,
    String? displayLabel,
    List<SocialStoryDrawStroke>? strokes,
    bool? locked,
  }) {
    return SocialStoryLayer(
      id: id,
      type: type,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
      text: text ?? this.text,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      textAlign: textAlign ?? this.textAlign,
      fontScale: fontScale ?? this.fontScale,
      sticker: sticker ?? this.sticker,
      mentionedUserId: mentionedUserId ?? this.mentionedUserId,
      displayLabel: displayLabel ?? this.displayLabel,
      strokes: strokes ?? this.strokes,
      locked: locked ?? this.locked,
    );
  }
}

class SocialStoryDraft {
  final String draftId;
  final int version;
  final SocialStoryComposerMode mode;
  final String caption;
  final String? mediaPath;
  final String? mediaName;
  final String? mediaMimeType;
  final String? filterId;
  final String? effectId;
  final String? captureSource;
  final SocialStoryBackground background;
  final SocialStoryAttachment? attachment;
  final List<SocialStoryLayer> layers;

  // ── Maslaki unique feature metadata ──────────────────────────────────────
  final String? timeMoodKey;
  final String? placePulseLabel;
  final bool hasMaslakiSeal;
  final String? maslakiMoodKey;

  const SocialStoryDraft({
    required this.draftId,
    required this.version,
    required this.mode,
    required this.caption,
    required this.mediaPath,
    required this.mediaName,
    required this.mediaMimeType,
    required this.filterId,
    required this.effectId,
    required this.captureSource,
    required this.background,
    required this.attachment,
    required this.layers,
    this.timeMoodKey,
    this.placePulseLabel,
    this.hasMaslakiSeal = false,
    this.maslakiMoodKey,
  });

  factory SocialStoryDraft.initialText() => SocialStoryDraft(
    draftId: DateTime.now().microsecondsSinceEpoch.toString(),
    version: 2,
    mode: SocialStoryComposerMode.text,
      caption: '',
      mediaPath: null,
      mediaName: null,
      mediaMimeType: null,
      filterId: null,
      effectId: null,
      captureSource: null,
      background: const SocialStoryBackground(
        type: SocialStoryBackgroundType.gradient,
        primaryColor: '#1E3A8A',
      secondaryColor: '#0F766E',
      imageUrl: null,
    ),
    attachment: null,
    layers: const <SocialStoryLayer>[],
  );

  factory SocialStoryDraft.fromJson(Map<String, dynamic> json) {
    final rawMode = parseString(json['mode'], fallback: 'text');
    return SocialStoryDraft(
      draftId: parseString(json['draftId'] ?? json['draft_id']),
      version: parseInt(json['version'] ?? 2),
      mode: SocialStoryComposerMode.values.firstWhere(
        (value) => value.name == rawMode,
        orElse: () => SocialStoryComposerMode.text,
      ),
      caption: parseString(json['caption'], fallback: ''),
      mediaPath: parseNullableString(json['mediaPath'] ?? json['media_path']),
      mediaName: parseNullableString(json['mediaName'] ?? json['media_name']),
      mediaMimeType: parseNullableString(
        json['mediaMimeType'] ?? json['media_mime_type'],
      ),
      filterId: parseNullableString(json['filterId'] ?? json['filter_id']),
      effectId: parseNullableString(json['effectId'] ?? json['effect_id']),
      captureSource: parseNullableString(
        json['captureSource'] ?? json['capture_source'],
      ),
      timeMoodKey: parseNullableString(
        json['timeMoodKey'] ?? json['time_mood_key'],
      ),
      placePulseLabel: parseNullableString(
        json['placePulseLabel'] ?? json['place_pulse_label'],
      ),
      hasMaslakiSeal: parseBool(
        json['hasMaslakiSeal'] ?? json['has_maslaki_seal'],
      ),
      maslakiMoodKey: parseNullableString(
        json['maslakiMoodKey'] ?? json['maslaki_mood_key'],
      ),
      background: SocialStoryBackground.fromJson(
        Map<String, dynamic>.from(json['background'] as Map? ?? const {}),
      ),
      attachment: json['attachment'] is Map
          ? SocialStoryAttachment.fromJson(
              Map<String, dynamic>.from(json['attachment'] as Map),
            )
          : null,
      layers: List<dynamic>.from(json['layers'] as List? ?? const [])
          .map(
            (item) => SocialStoryLayer.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  factory SocialStoryDraft.fromStoryStyle({required SocialStory story}) {
    final raw = story.style.rawDocument;
    if (raw['version'] == 2) {
      return SocialStoryDraft.fromJson(raw);
    }
    final hasMedia = (story.mediaUrl ?? '').trim().isNotEmpty;
    final attachment = story.style.sharedPostId != null
        ? SocialStoryAttachment(
            type: 'post_share',
            reelId: null,
            postId: story.style.sharedPostId,
            authorName: story.style.sharedPostAuthor,
            posterUrl: story.style.sharedPostMediaUrl,
            caption: story.style.sharedPostCaption,
            mediaUrl: story.style.sharedPostMediaUrl,
            mediaKind: story.style.sharedPostMediaKind,
            label: null,
          )
        : null;
    return SocialStoryDraft(
      draftId: story.id.toString(),
      version: 2,
      mode: attachment == null
          ? (story.mediaUrl == null
                ? SocialStoryComposerMode.text
                : SocialStoryComposerMode.media)
          : SocialStoryComposerMode.postShare,
      caption: story.caption,
      mediaPath: null,
      mediaName: null,
      mediaMimeType: story.mediaKind,
      filterId: parseNullableString(raw['filterId'] ?? raw['filter_id']),
      effectId: parseNullableString(raw['effectId'] ?? raw['effect_id']),
      captureSource: parseNullableString(
        raw['captureSource'] ?? raw['capture_source'],
      ),
      background: SocialStoryBackground(
        type: SocialStoryBackgroundType.solid,
        primaryColor: story.style.backgroundColor,
        secondaryColor: null,
        imageUrl: story.style.sharedPostMediaUrl,
      ),
      attachment: attachment,
      layers: [
        if (story.caption.trim().isNotEmpty)
          SocialStoryLayer(
            id: 'legacy-text',
            type: SocialStoryLayerType.text,
            x: 0.5,
            y: attachment == null ? (hasMedia ? 0.82 : 0.5) : 0.22,
            scale: 1,
            rotation: 0,
            zIndex: 10,
            text: story.caption.trim(),
            color: story.style.textColor,
            backgroundColor: hasMedia ? '#66000000' : null,
            fontFamily: story.style.fontFamily,
            fontWeight: story.style.fontWeight,
            textAlign: story.style.textAlign,
            fontScale: story.style.fontScale,
            sticker: null,
            mentionedUserId: null,
            displayLabel: null,
          ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'draftId': draftId,
    'version': version,
    'mode': mode.name,
    'caption': caption,
    if (mediaPath != null) 'mediaPath': mediaPath,
    if (mediaName != null) 'mediaName': mediaName,
    if (mediaMimeType != null) 'mediaMimeType': mediaMimeType,
    if (filterId != null) 'filterId': filterId,
    if (effectId != null) 'effectId': effectId,
    if (captureSource != null) 'captureSource': captureSource,
    if ((timeMoodKey ?? '').trim().isNotEmpty) 'timeMoodKey': timeMoodKey,
    if ((placePulseLabel ?? '').trim().isNotEmpty) 'placePulseLabel': placePulseLabel,
    if (hasMaslakiSeal) 'hasMaslakiSeal': true,
    if ((maslakiMoodKey ?? '').trim().isNotEmpty) 'maslakiMoodKey': maslakiMoodKey,
    'background': background.toJson(),
    if (attachment != null) 'attachment': attachment!.toJson(),
    'layers': layers.map((layer) => layer.toJson()).toList(growable: false),
  };

  Map<String, dynamic> toStoryStyleJson() => toJson();

  SocialStoryDraft copyWith({
    SocialStoryComposerMode? mode,
    String? caption,
    String? mediaPath,
    String? mediaName,
    String? mediaMimeType,
    String? filterId,
    String? effectId,
    String? captureSource,
    SocialStoryBackground? background,
    SocialStoryAttachment? attachment,
    bool clearAttachment = false,
    List<SocialStoryLayer>? layers,
    String? timeMoodKey,
    String? placePulseLabel,
    bool? hasMaslakiSeal,
    String? maslakiMoodKey,
  }) {
    return SocialStoryDraft(
      draftId: draftId,
      version: version,
      mode: mode ?? this.mode,
      caption: caption ?? this.caption,
      mediaPath: mediaPath ?? this.mediaPath,
      mediaName: mediaName ?? this.mediaName,
      mediaMimeType: mediaMimeType ?? this.mediaMimeType,
      filterId: filterId ?? this.filterId,
      effectId: effectId ?? this.effectId,
      captureSource: captureSource ?? this.captureSource,
      background: background ?? this.background,
      attachment: clearAttachment ? null : (attachment ?? this.attachment),
      layers: layers ?? this.layers,
      timeMoodKey: timeMoodKey ?? this.timeMoodKey,
      placePulseLabel: placePulseLabel ?? this.placePulseLabel,
      hasMaslakiSeal: hasMaslakiSeal ?? this.hasMaslakiSeal,
      maslakiMoodKey: maslakiMoodKey ?? this.maslakiMoodKey,
    );
  }

  LocalMediaFile? buildLocalMediaFile() {
    final path = (mediaPath ?? '').trim();
    if (path.isEmpty) return null;
    return LocalMediaFile(
      name: mediaName ?? 'story-media',
      path: path,
      bytes: null,
      mimeType: mediaMimeType,
    );
  }
}

SocialStoryDraft buildReelShareDraft(SocialReelItem item) {
  final poster =
      item.post.asset?.posterUrl ??
      item.post.asset?.normalizedUrl ??
      item.post.mediaUrl;
  final attachment = SocialStoryAttachment(
    type: 'reel_share',
    reelId: item.post.id,
    postId: null,
    authorName: (item.post.author.username ?? '').trim().isNotEmpty
        ? '@${item.post.author.username!.trim()}'
        : item.post.author.fullName,
    posterUrl: poster,
    caption: item.post.caption,
    mediaUrl: item.post.mediaUrl,
    mediaKind: item.post.mediaKind,
    label: 'Watch reel',
  );
  return SocialStoryDraft.initialText().copyWith(
    mode: SocialStoryComposerMode.reelShare,
    caption: item.post.caption.trim(),
    background: SocialStoryBackground(
      type: poster == null || poster.trim().isEmpty
          ? SocialStoryBackgroundType.gradient
          : SocialStoryBackgroundType.posterBlur,
      primaryColor: '#0F172A',
      secondaryColor: '#1D4ED8',
      imageUrl: poster,
    ),
    attachment: attachment,
    layers: [
      SocialStoryLayer(
        id: 'reel-card',
        type: SocialStoryLayerType.reelShare,
        x: 0.5,
        y: 0.56,
        scale: 1,
        rotation: 0,
        zIndex: 20,
        text: null,
        color: null,
        backgroundColor: null,
        fontFamily: null,
        fontWeight: null,
        textAlign: null,
        fontScale: null,
        sticker: null,
        mentionedUserId: null,
        displayLabel: null,
        locked: false,
      ),
    ],
  );
}

SocialStoryDraft buildPostShareDraft(SocialPost post) {
  final attachment = SocialStoryAttachment(
    type: 'post_share',
    reelId: null,
    postId: post.id,
    authorName: (post.author.username ?? '').trim().isNotEmpty
        ? '@${post.author.username!.trim()}'
        : post.author.fullName,
    posterUrl: post.mediaUrl,
    caption: post.caption,
    mediaUrl: post.mediaUrl,
    mediaKind: post.mediaKind,
    label: 'View post',
  );
  return SocialStoryDraft.initialText().copyWith(
    mode: SocialStoryComposerMode.postShare,
    caption: post.caption.trim(),
    background: SocialStoryBackground(
      type: (post.mediaUrl ?? '').trim().isEmpty
          ? SocialStoryBackgroundType.gradient
          : SocialStoryBackgroundType.posterBlur,
      primaryColor: '#1E3A8A',
      secondaryColor: '#0F766E',
      imageUrl: post.mediaUrl,
    ),
    attachment: attachment,
    layers: [
      SocialStoryLayer(
        id: 'post-card',
        type: SocialStoryLayerType.postShare,
        x: 0.5,
        y: 0.56,
        scale: 1,
        rotation: 0,
        zIndex: 20,
        text: null,
        color: null,
        backgroundColor: null,
        fontFamily: null,
        fontWeight: null,
        textAlign: null,
        fontScale: null,
        sticker: null,
        mentionedUserId: null,
        displayLabel: null,
        locked: false,
      ),
    ],
  );
}
