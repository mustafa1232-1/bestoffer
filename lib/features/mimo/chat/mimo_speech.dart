import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Mimo's ears and mouth, using the phone's own (free, on-device) speech
/// recognition and text-to-speech. No paid cloud voice service.
abstract class MimoSpeech {
  /// Starts listening; [onText] gets the live transcript, `isFinal` once the
  /// user stops talking. Returns false if the mic/recognizer is unavailable.
  Future<bool> listen({
    required String lang,
    required void Function(String text, bool isFinal) onText,
  });

  Future<void> stopListening();

  /// Reads [text] aloud (stops anything already being read).
  Future<void> speak(String text, {required String lang});

  Future<void> stopSpeaking();
}

final mimoSpeechProvider = Provider<MimoSpeech>((ref) {
  final speech = DeviceMimoSpeech();
  ref.onDispose(speech.dispose);
  return speech;
});

/// Whether Mimo reads his replies aloud (toggled from the chat header).
final mimoSpeakRepliesProvider = StateProvider<bool>((ref) => false);

class DeviceMimoSpeech implements MimoSpeech {
  final SpeechToText _stt = SpeechToText();
  FlutterTts? _tts;
  bool _sttReady = false;

  Future<FlutterTts> _ensureTts() async {
    final existing = _tts;
    if (existing != null) return existing;
    final tts = FlutterTts();
    await tts.awaitSpeakCompletion(false);
    _tts = tts;
    return tts;
  }

  @override
  Future<bool> listen({
    required String lang,
    required void Function(String text, bool isFinal) onText,
  }) async {
    try {
      if (!_sttReady) {
        _sttReady = await _stt.initialize(onError: (_) {});
      }
      if (!_sttReady) return false;
      final localeId = await _pickLocale(lang);
      await _stt.listen(
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
        onResult: (r) => onText(r.recognizedWords, r.finalResult),
      );
      return true;
    } catch (e) {
      debugPrint('[mimo-speech] listen failed: $e');
      return false;
    }
  }

  /// Iraqi Arabic when the phone has it, otherwise any Arabic.
  Future<String?> _pickLocale(String lang) async {
    final locales = await _stt.locales();
    final ids = locales.map((l) => l.localeId.replaceAll('-', '_')).toList();
    final wanted = lang == 'en'
        ? const ['en_US', 'en_GB']
        : const ['ar_IQ', 'ar_SA', 'ar_EG', 'ar_AE', 'ar_JO'];
    for (final w in wanted) {
      final i = ids.indexWhere((id) => id.toLowerCase() == w.toLowerCase());
      if (i >= 0) return locales[i].localeId;
    }
    final prefix = lang == 'en' ? 'en' : 'ar';
    final i = ids.indexWhere((id) => id.toLowerCase().startsWith(prefix));
    return i >= 0 ? locales[i].localeId : null;
  }

  @override
  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }

  @override
  Future<void> speak(String text, {required String lang}) async {
    final clean = mimoSpeakableText(text);
    if (clean.isEmpty) return;
    try {
      final tts = await _ensureTts();
      await tts.stop();
      final langs = (await tts.getLanguages as List?)?.cast<Object?>() ?? [];
      final codes = langs.map((e) => '$e').toList();
      final wanted = lang == 'en'
          ? const ['en-US', 'en-GB']
          : const ['ar-IQ', 'ar-SA', 'ar'];
      final pick = wanted.firstWhere(
        (w) => codes.any((c) => c.toLowerCase() == w.toLowerCase()),
        orElse: () => lang == 'en' ? 'en-US' : 'ar',
      );
      await tts.setLanguage(pick);
      // A bit higher and quicker: a small, cheerful character.
      await tts.setPitch(1.35);
      await tts.setSpeechRate(0.5);
      await tts.speak(clean);
    } catch (e) {
      debugPrint('[mimo-speech] speak failed: $e');
    }
  }

  @override
  Future<void> stopSpeaking() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  void dispose() {
    stopListening();
    stopSpeaking();
  }
}

/// Text that sounds right when read aloud: no emoji, links or markdown.
String mimoSpeakableText(String text) => text
    .replaceAll(RegExp(r'https?://\S+'), '')
    .replaceAll(RegExp(r'[*_`#>\[\]]'), '')
    .replaceAll(
      RegExp(
        r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]',
        unicode: true,
      ),
      '',
    )
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
