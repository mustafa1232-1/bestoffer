import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../data/social_story_draft_storage.dart';
import '../models/social_story_document.dart';

final socialStoryDraftStorageProvider = Provider<SocialStoryDraftStorage>((
  ref,
) {
  return SocialStoryDraftStorage(SecureStore());
});

enum SocialStoryComposerTool { none, text, mention, stickers, draw, media }

class SocialStoryDraftState {
  final SocialStoryDraft draft;
  final String? selectedLayerId;
  final SocialStoryComposerTool activeTool;

  const SocialStoryDraftState({
    required this.draft,
    required this.selectedLayerId,
    this.activeTool = SocialStoryComposerTool.none,
  });

  SocialStoryDraftState copyWith({
    SocialStoryDraft? draft,
    String? selectedLayerId,
    bool clearSelection = false,
    SocialStoryComposerTool? activeTool,
  }) {
    return SocialStoryDraftState(
      draft: draft ?? this.draft,
      selectedLayerId: clearSelection
          ? null
          : (selectedLayerId ?? this.selectedLayerId),
      activeTool: activeTool ?? this.activeTool,
    );
  }
}

final socialStoryDraftControllerProvider =
    StateNotifierProvider.autoDispose<
      SocialStoryDraftController,
      SocialStoryDraftState
    >((ref) {
      return SocialStoryDraftController(ref);
    });

class SocialStoryDraftController extends StateNotifier<SocialStoryDraftState> {
  final Ref ref;

  SocialStoryDraftController(this.ref)
    : super(
        SocialStoryDraftState(
          draft: SocialStoryDraft.initialText(),
          selectedLayerId: null,
        ),
      );

  Future<void> restoreLastDraft() async {
    final draft = await ref.read(socialStoryDraftStorageProvider).load();
    if (draft == null) return;
    state = state.copyWith(draft: draft, clearSelection: true);
  }

  Future<void> saveDraft() {
    return ref.read(socialStoryDraftStorageProvider).save(state.draft);
  }

  Future<void> clearPersistedDraft() {
    return ref.read(socialStoryDraftStorageProvider).clear();
  }

  void replaceDraft(SocialStoryDraft draft) {
    state = state.copyWith(draft: draft, clearSelection: true);
  }

  void setMode(SocialStoryComposerMode mode) {
    state = state.copyWith(draft: state.draft.copyWith(mode: mode));
  }

  void setTool(SocialStoryComposerTool tool) {
    state = state.copyWith(activeTool: tool);
  }

  void setCaption(String caption) {
    state = state.copyWith(draft: state.draft.copyWith(caption: caption));
  }

  void setBackground(SocialStoryBackground background) {
    state = state.copyWith(draft: state.draft.copyWith(background: background));
  }

  void setMedia({String? path, String? name, String? mimeType}) {
    state = state.copyWith(
      draft: state.draft.copyWith(
        mediaPath: path,
        mediaName: name,
        mediaMimeType: mimeType,
      ),
    );
  }

  void setAttachment(SocialStoryAttachment attachment) {
    state = state.copyWith(draft: state.draft.copyWith(attachment: attachment));
  }

  void clearAttachment() {
    state = state.copyWith(draft: state.draft.copyWith(clearAttachment: true));
  }

  void selectLayer(String? layerId) {
    if (layerId == null) {
      state = state.copyWith(clearSelection: true);
      return;
    }
    final layer = state.draft.layers
        .where((item) => item.id == layerId)
        .firstOrNull;
    if (layer == null) return;
    final topZ = state.draft.layers
        .map((item) => item.zIndex)
        .fold<int>(0, (max, value) => value > max ? value : max);
    final nextLayers = state.draft.layers
        .map(
          (item) => item.id == layerId && item.zIndex < topZ
              ? item.copyWith(zIndex: topZ + 1)
              : item,
        )
        .toList(growable: false);
    state = state.copyWith(
      draft: state.draft.copyWith(layers: nextLayers),
      selectedLayerId: layerId,
    );
  }

  void addTextLayer({String text = '', String color = '#FFFFFF'}) {
    final layers = [...state.draft.layers];
    final layer = SocialStoryLayer(
      id: 'layer-${DateTime.now().microsecondsSinceEpoch}',
      type: SocialStoryLayerType.text,
      x: 0.5,
      y: 0.5,
      scale: 1,
      rotation: 0,
      zIndex: layers.length + 1,
      text: text,
      color: color,
      backgroundColor: null,
      fontFamily: 'system',
      fontWeight: 'bold',
      textAlign: 'center',
      fontScale: 1.0,
      sticker: null,
      mentionedUserId: null,
      displayLabel: null,
    );
    layers.add(layer);
    state = state.copyWith(
      draft: state.draft.copyWith(layers: layers),
      selectedLayerId: layer.id,
      activeTool: SocialStoryComposerTool.text,
    );
  }

  void addMentionLayer({
    required int userId,
    required String displayLabel,
    String color = '#FFFFFF',
  }) {
    final label = displayLabel.trim();
    if (userId <= 0 || label.isEmpty) return;
    final layers = [...state.draft.layers];
    final layer = SocialStoryLayer(
      id: 'layer-${DateTime.now().microsecondsSinceEpoch}',
      type: SocialStoryLayerType.mention,
      x: 0.5,
      y: 0.38,
      scale: 1,
      rotation: 0,
      zIndex: layers.length + 1,
      text: '@$label',
      color: color,
      backgroundColor: '#26000000',
      fontFamily: 'system',
      fontWeight: 'bold',
      textAlign: 'center',
      fontScale: 1.0,
      sticker: null,
      mentionedUserId: userId,
      displayLabel: label,
    );
    layers.add(layer);
    state = state.copyWith(
      draft: state.draft.copyWith(layers: layers),
      selectedLayerId: layer.id,
      activeTool: SocialStoryComposerTool.mention,
    );
  }

  void addStickerLayer(String sticker) {
    final layers = [...state.draft.layers];
    final layer = SocialStoryLayer(
      id: 'layer-${DateTime.now().microsecondsSinceEpoch}',
      type: SocialStoryLayerType.sticker,
      x: 0.5,
      y: 0.5,
      scale: 1,
      rotation: 0,
      zIndex: layers.length + 1,
      text: null,
      color: '#FFFFFF',
      backgroundColor: null,
      fontFamily: null,
      fontWeight: null,
      textAlign: null,
      fontScale: null,
      sticker: sticker,
      mentionedUserId: null,
      displayLabel: null,
    );
    layers.add(layer);
    state = state.copyWith(
      draft: state.draft.copyWith(layers: layers),
      selectedLayerId: layer.id,
      activeTool: SocialStoryComposerTool.stickers,
    );
  }

  void updateLayer(String layerId, SocialStoryLayer nextLayer) {
    final layers = state.draft.layers
        .map((layer) => layer.id == layerId ? nextLayer : layer)
        .toList(growable: false);
    state = state.copyWith(draft: state.draft.copyWith(layers: layers));
  }

  void updateSelectedTextLayer({
    String? text,
    String? color,
    String? backgroundColor,
    String? fontFamily,
    String? fontWeight,
    String? textAlign,
    double? fontScale,
  }) {
    final layerId = state.selectedLayerId;
    if (layerId == null) return;
    final layer = state.draft.layers
        .where((item) => item.id == layerId)
        .firstOrNull;
    if (layer == null) return;
    updateLayer(
      layerId,
      layer.copyWith(
        text: text,
        color: color,
        backgroundColor: backgroundColor,
        fontFamily: fontFamily,
        fontWeight: fontWeight,
        textAlign: textAlign,
        fontScale: fontScale,
      ),
    );
  }

  void moveLayer({
    required String layerId,
    required double x,
    required double y,
    required double scale,
    required double rotation,
  }) {
    final layer = state.draft.layers
        .where((item) => item.id == layerId)
        .firstOrNull;
    if (layer == null || layer.locked) return;
    updateLayer(
      layerId,
      layer.copyWith(
        x: x.clamp(0.08, 0.92),
        y: y.clamp(0.08, 0.92),
        scale: scale.clamp(0.55, 2.4),
        rotation: rotation,
      ),
    );
  }

  void addDrawStroke(SocialStoryDrawStroke stroke) {
    final existingIndex = state.draft.layers.indexWhere(
      (layer) => layer.type == SocialStoryLayerType.draw,
    );
    if (existingIndex >= 0) {
      final layer = state.draft.layers[existingIndex];
      updateLayer(
        layer.id,
        layer.copyWith(strokes: [...layer.strokes, stroke]),
      );
      return;
    }
    final layers = [...state.draft.layers];
    final layer = SocialStoryLayer(
      id: 'layer-${DateTime.now().microsecondsSinceEpoch}',
      type: SocialStoryLayerType.draw,
      x: 0.5,
      y: 0.5,
      scale: 1,
      rotation: 0,
      zIndex: layers.length + 1,
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
      strokes: [stroke],
      locked: true,
    );
    layers.add(layer);
    state = state.copyWith(draft: state.draft.copyWith(layers: layers));
  }

  void removeSelectedLayer() {
    final layerId = state.selectedLayerId;
    if (layerId == null) return;
    final layers = state.draft.layers
        .where((layer) => layer.id != layerId)
        .toList(growable: false);
    state = state.copyWith(
      draft: state.draft.copyWith(layers: layers),
      clearSelection: true,
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
