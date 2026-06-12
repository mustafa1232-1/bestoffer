# Deployment Guide

## Build prerequisites
- Configure all required env keys.
- Ensure migration 113 applied.

## Backend deploy
- Install deps and run `npm start`.
- Validate `/ready` and `/version`.

## Flutter builds
- Android: `flutter build apk`
- iOS: `flutter build ios`
- Web: `flutter build web`
- Windows: `flutter build windows`

## Post-deploy
- Open AI DEV SUPPORT and verify integration statuses.
