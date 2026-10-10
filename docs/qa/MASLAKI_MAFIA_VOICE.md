# Maslaki Mafia Voice Runbook

Mafia voice uses a LiveKit SFU. It intentionally does not reuse the social
call mesh because a Mafia room can contain fourteen concurrent listeners.

## Required backend variables

- `LIVEKIT_URL`: public `wss://` endpoint used by Flutter and the installed PWA.
- `LIVEKIT_API_KEY`: server-side key used only by the backend.
- `LIVEKIT_API_SECRET`: server-side secret used only by the backend.
- `LIVEKIT_TOKEN_TTL_SEC`: short token lifetime; the default is 900 seconds.

Never expose the key or secret in Flutter, Firebase Hosting, or browser assets.
The backend issues a room-scoped token after verifying Mafia membership.

## Network requirements

- Serve LiveKit and the web app over TLS.
- Configure UDP plus TURN/TLS fallback for mobile networks and restrictive Wi-Fi.
- Keep the LiveKit WebSocket origin in the backend CSP `connect-src` policy.
- Keep first-party microphone permission enabled in `Permissions-Policy`.

## Release verification

1. Join one room from an Android device and one installed iPhone PWA on separate
   networks.
2. Verify lobby audio, night Mafia-only audio, discussion audio, candidate-only
   defense, muted voting, eliminated-player restrictions, and final-room audio.
3. Revoke microphone permission and verify the UI reports the denial without
   breaking the game state.
4. Background and resume both clients, then confirm that voice reconnects and
   only one realtime room subscription remains active.
5. Run a fourteen-participant soak test for at least thirty minutes and inspect
   LiveKit packet loss, reconnect count, RTT, and server CPU/network metrics.

## Failure behavior

If LiveKit is not configured or temporarily unavailable, Mafia gameplay,
timers, chat, voting, and role actions remain available. The voice bar reports
the failure and offers reconnect; the backend never grants camera or screen
share publication for Mafia rooms.
