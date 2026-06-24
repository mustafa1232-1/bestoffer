TURN deployment notes

- The app now fetches TURN credentials dynamically from `/api/system/rtc-config`.
- The backend generates temporary credentials using `RTC_TURN_SECRET`.
- `coturn` must use the same secret as `TURN_AUTH_SECRET`.

Recommended production hosting

- Host TURN on a VM or container platform that exposes:
  - `3478/tcp`
  - `3478/udp`
  - a relay port range such as `49160-49200/tcp+udp`
- Railway is not suitable for strict production TURN relay because public UDP and relay port ranges are not exposed the way TURN normally needs.

Managed alternative

- The backend also supports `Twilio Network Traversal Service`.
- Set:
  - `RTC_TURN_PROVIDER=twilio`
  - `TWILIO_ACCOUNT_SID`
  - `TWILIO_AUTH_TOKEN`
  - `TWILIO_NTS_TTL_SEC`
- Clients fetch temporary ICE servers from `/api/system/rtc-config` automatically.

Minimum environment

- `TURN_AUTH_SECRET`
- `TURN_REALM`
- `TURN_PUBLIC_IP` or `TURN_PUBLIC_HOST`
- `TURN_PORT=3478`
- `TURN_MIN_PORT=49160`
- `TURN_MAX_PORT=49200`

Backend environment

- `RTC_TURN_ENABLED=true`
- `RTC_TURN_SECRET=<same TURN_AUTH_SECRET>`
- `RTC_TURN_URLS=turn:turn.example.com:3478?transport=udp,turn:turn.example.com:3478?transport=tcp`
- `RTC_TURN_CREDENTIAL_TTL_SEC=21600`
