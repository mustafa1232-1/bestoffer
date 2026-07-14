import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/capabilities/social_capabilities.dart';
import 'package:maslaki/features/social_v3/capabilities/social_capabilities_api.dart';
import 'package:maslaki/features/social_v3/capabilities/social_capabilities_controller.dart';

class _FakeApi extends SocialCapabilitiesApi {
  _FakeApi(this._result) : super(Dio());
  SocialCapabilities _result;
  int calls = 0;
  @override
  Future<SocialCapabilities> fetch() async {
    calls++;
    return _result;
  }

  void setResult(SocialCapabilities r) => _result = r;
}

SocialCapabilities _caps({required bool supported, List<String>? types}) =>
    SocialCapabilities(
      storyAudienceScope: StoryAudienceScopeCapability(
        supported: supported,
        supportedTypes: types ?? (supported ? const ['global', 'building'] : const ['global']),
        officialStoriesSupported: false,
        version: 1,
        reason: supported ? 'ENABLED' : 'IMPLEMENTATION_INCOMPLETE',
      ),
    );

void main() {
  group('SocialCapabilities parsing (fail-closed)', () {
    test('disabled payload → only global', () {
      final c = SocialCapabilities.fromJson({
        'social': {
          'storyAudienceScope': {
            'supported': false,
            'supportedTypes': ['global'],
            'reason': 'IMPLEMENTATION_INCOMPLETE',
          },
        },
      });
      expect(c.storyAudienceScope.supported, isFalse);
      expect(c.storyAudienceScope.supportedTypes, ['global']);
      expect(c.storyAudienceScope.supportsType('building'), isFalse);
    });

    test('supported=false ignores any advertised types (fail-closed)', () {
      final c = SocialCapabilities.fromJson({
        'social': {
          'storyAudienceScope': {
            'supported': false,
            'supportedTypes': ['global', 'building'], // must be ignored
          },
        },
      });
      expect(c.storyAudienceScope.supportedTypes, ['global']);
    });

    test('enabled payload exposes its types', () {
      final c = SocialCapabilities.fromJson({
        'social': {
          'storyAudienceScope': {
            'supported': true,
            'supportedTypes': ['global', 'block', 'compound', 'building'],
          },
        },
      });
      expect(c.storyAudienceScope.supportsType('building'), isTrue);
      expect(c.storyAudienceScope.supportsType('area'), isFalse);
    });

    test('missing/malformed → fail-closed', () {
      expect(SocialCapabilities.fromJson(null).storyAudienceScope.supported, isFalse);
      expect(SocialCapabilities.fromJson({}).storyAudienceScope.supported, isFalse);
      expect(
        SocialCapabilities.fromJson({'social': 'nope'}).storyAudienceScope.supportedTypes,
        ['global'],
      );
    });
  });

  group('SocialCapabilitiesController', () {
    test('starts fail-closed and fetches on ensureFresh', () async {
      final api = _FakeApi(_caps(supported: true));
      final c = SocialCapabilitiesController(api);
      expect(c.state.storyAudienceScope.supported, isFalse); // default
      await c.ensureFresh();
      expect(c.state.storyAudienceScope.supported, isTrue);
      expect(api.calls, 1);
    });

    test('bounded cache: ensureFresh does not refetch until TTL elapses', () async {
      var now = DateTime(2026, 1, 1);
      final api = _FakeApi(_caps(supported: true));
      final c = SocialCapabilitiesController(
        api,
        cacheTtl: const Duration(minutes: 5),
        clock: () => now,
      );
      await c.ensureFresh();
      await c.ensureFresh(); // within TTL → no refetch
      expect(api.calls, 1);
      now = now.add(const Duration(minutes: 6));
      await c.ensureFresh(); // stale → refetch
      expect(api.calls, 2);
    });

    test('network error → fail-closed (real API path)', () async {
      // The real API returns failClosed on any Dio error.
      final api = SocialCapabilitiesApi(
        Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'))
          ..options.connectTimeout = const Duration(milliseconds: 50),
      );
      final caps = await api.fetch();
      expect(caps.storyAudienceScope.supported, isFalse);
      expect(caps.storyAudienceScope.supportedTypes, ['global']);
    });

    test('stale supported=true → markStoryScopeUnsupported resets to fail-closed',
        () async {
      final api = _FakeApi(_caps(supported: true));
      final c = SocialCapabilitiesController(api);
      await c.ensureFresh();
      expect(c.state.storyAudienceScope.supported, isTrue);
      // Simulate a server 409 after a stale positive cache.
      c.markStoryScopeUnsupported();
      expect(c.state.storyAudienceScope.supported, isFalse);
      // Next ensureFresh refetches authoritative state.
      api.setResult(_caps(supported: false));
      await c.ensureFresh();
      expect(c.state.storyAudienceScope.supported, isFalse);
      expect(api.calls, 2);
    });
  });
}
