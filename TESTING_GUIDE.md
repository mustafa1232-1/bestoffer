# Testing Guide

## Backend
- Run: `cd backend && npm test`
- Focused ops tests: `node --test "src/tests/ops*.test.js"`

## Flutter
- Run: `flutter test`
- AI dashboard widget tests: `test/core/ai_dev_support_dashboard_screen_test.dart`

## Manual checks
- Webhook auth using `OPS_API_KEY`
- Super admin only access
- Critical action typed confirmation
