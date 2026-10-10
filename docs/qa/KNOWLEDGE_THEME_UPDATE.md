# Knowledge Map Illustrated Theme

Date: 2026-10-08. Scope: the reference-inspired match presentation, not a rules migration or production release.

Follow-up: [Tournament series and bracket implementation](KNOWLEDGE_TOURNAMENT_SERIES.md) adds best-of games and documents its separate migration, tests and release limits.

## Delivered

- Eleven illustrated Iraqi-inspired landmarks, ownership flags, dashed routes based on real server adjacency, a green/burgundy competition header, question progress and trophy art.
- Selection/ownership animation moves the landmark, not its hit target. Reduced motion disables the effect. The countdown has its own repaint lifecycle.
- One bundled transparent sprite atlas is decoded once and shared by all landmarks; there are no per-region network image downloads.
- Answer rewards now come from additive backend `question.scoring` metadata using the same constants as the score calculation. Older snapshots without that metadata omit the reward rather than invent a number.
- Regions show `+1 منطقة`, occupied or unavailable status. Ownership is still updated only from the server, not optimistically painted as a conquest.
- A browser accessibility issue was reproduced: inherited HTML RTL moved the souk's semantic hit rectangle to x=539 outside a 390px viewport while its art was at x=261. Isolating `flutter-view` to LTR fixes the coordinate layer; Flutter `Directionality` preserves the Arabic UI. The territory exposes one accessible action rather than duplicate tooltip/text labels.

## Actual Rules

Correct answers earn 100 (easy), 150 (medium), or 200 (hard), plus up to 50 for remaining time. Incorrect answers earn zero. These values were not changed.

Regions do **not** add score or have different point prices. Their connections determine future expansion. After a tied total score, the existing tie-break compares correct rounds, response time, then territory count. No priority rule, answer admission, server deadline or team vote rule was changed. The existing same-target priority for team A remains a separate product decision documented in `KNOWLEDGE_MAP_REBUILD.md`.

## Evidence

- Full Flutter suite: 864 passed, one skipped (`knowledge-theme-flutter-full.log`). This run preceded the final singular/plural copy correction; final game tests separately cover that correction.
- Game Flutter tests: 46 passed, one skipped (`knowledge-theme-flutter.log`). Includes RTL 360/390/900 widths, 320px enlarged text with keyboard, fixed selection hit bounds during animation, all eleven rendered landmarks, ownership/frontier selection, image pixel checks and goldens.
- Backend targeted scoring, voting and real round DB tests: 26 passed, zero failed (`knowledge-theme-backend.log`). Displayed rewards match actual scoring.
- Browser test: actual Flutter match screen + games HTTP router + isolated local PostgreSQL. One HTTP 200 durable answer receipt, visible confirmation, chat expansion, reduced-motion switch and no browser page errors. `knowledge-web-report.json` and `test_driver/knowledge_browser_check.cjs` reproduce the flow.
- `flutter analyze`: no issues found (`knowledge-theme-analyze.log`).

Screenshots: [phone](knowledge-web-phone.png), [confirmed answer](knowledge-web-confirmed.png), [map](knowledge-theme-map-browser.png), [desktop](knowledge-web-desktop.png), [settings](knowledge-web-settings.png). Illustrated ownership golden: `test/features/games/goldens/knowledge-map-illustrated.png`.

## Asset Provenance

Generated with built-in image generation, new-image mode and transparent background. Saved as `assets/games/knowledge/landmarks-v1.png` (1536x1024, four columns by three rows). Exact generation prompt, original saved source and mode: [knowledge-theme-art.json](knowledge-theme-art.json). The prompt describes isolated isometric miniatures, not a flattened UI screenshot; text and interaction are actual Flutter widgets.

## Limits

No Android/iPhone hardware frame profiling, physical screen-reader session or two-device LiveKit audio test was performed for this visual change. Browser QA uses a local test opponent and HTTP fallback, not production realtime latency. No 60fps or app-wide 100% claim is made. The earlier full-backend failures outside games remain documented in `KNOWLEDGE_MAP_REBUILD.md`; this report does not supersede them.

No version bump, AAB, production deployment or production data change. Local preview is `http://127.0.0.1:4879`, using the non-shipping `test_driver/knowledge_preview.dart` entrypoint and a loopback-only QA backend on port 4878.
