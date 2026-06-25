# Testing live FCM push for the delivery and user apps

This verifies that notifications arrive as **real FCM pushes** (not only local
channels) in all three app states: **foreground**, **background**, and
**terminated** — with sound, heads-up, and correct tap routing.

> ⚠️ Never commit a service account. Keep it out of git (e.g. under
> `backend/deploy/` which is git-ignored, or anywhere outside the repo) and
> reference it only through an environment variable.

## 1. What is already verified (in code / on device)

- FCM client handlers are all wired in `lib/core/notifications/push_notification_service.dart`:
  `onMessage` (foreground), `onMessageOpenedApp` (background tap),
  `getInitialMessage` (terminated launch), `onBackgroundMessage`
  (background/terminated), `onTokenRefresh`, and `requestPermission`.
- Token registration (`registerPushToken`) is **authenticated** — the backend
  ties the token to the signed-in user, so the user's role (delivery vs user)
  is known server-side; the delivery app registers the courier's token, the
  user app registers the customer's token.
- The four delivery channels exist and were confirmed created on an emulator
  (`maslaki_delivery_urgent_v1`, `_orders_v1`, `_chat_v1`, `_competitions_v1`)
  with the right importance + sound + vibration.
- Tap routing is unit-tested (`test/core/delivery_route_guard_test.dart`,
  notification navigation maps order→detail, chat→thread, etc.).

What cannot be verified without a service account: the **actual push
delivery** end-to-end.

## 2. Read the device FCM token

Run the app (logged in), then:

```bash
adb logcat -c
adb logcat | findstr /i "FirebaseMessaging token"
# or add a temporary debugPrint of the token in push_notification_service
```

## 3a. Send a test push with the Firebase CLI (simplest)

```bash
# Auth is interactive; no secret stored in the repo.
firebase login
firebase messaging:send --project maslaki-61a97 --token <DEVICE_TOKEN> ^
  --notification-title "طلب توصيل جديد" --notification-body "لديك طلب جاهز للاستلام"
```

## 3b. Send a test push with the FCM HTTP v1 API (full payload)

```bash
# Point this at a service account kept OUTSIDE git:
export GOOGLE_APPLICATION_CREDENTIALS="C:/secure/maslaki-service-account.json"

# Mint an access token (requires google-auth library or gcloud):
ACCESS_TOKEN=$(gcloud auth application-default print-access-token)

curl -X POST "https://fcm.googleapis.com/v1/projects/maslaki-61a97/messages:send" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "token": "<DEVICE_TOKEN>",
      "notification": { "title": "طلب جديد", "body": "طلب جاهز للاستلام" },
      "android": {
        "priority": "high",
        "notification": { "channel_id": "maslaki_delivery_urgent_v1", "sound": "default" }
      },
      "data": {
        "type": "delivery_order_assigned",
        "roleScope": "delivery",
        "orderId": "123",
        "target": "courier_orders_current",
        "channelId": "maslaki_delivery_urgent_v1",
        "priority": "high",
        "dedupeKey": "order-123-assigned"
      }
    }
  }'
```

## 4. What to check for each app state

| State | How to reach it | Expected |
|---|---|---|
| Foreground | App open | In-app local notification + sound; tap opens order detail |
| Background | Press home | Heads-up + sound; tap (`onMessageOpenedApp`) opens order detail |
| Terminated | Swipe app away | Heads-up + sound; tap (`getInitialMessage`) opens order detail after launch |

Delivery `data.target` values to try: `courier_orders_current` (order),
`courier_orders_new` (offer), chat thread via `threadId`, `courier_competitions`.
User `data.target`: order detail via `orderId`, `order_tracking` for live
tracking, social via `postId`/`reelId`/`storyId`.

## 5. Watch routing live

```bash
adb logcat -c
adb logcat | findstr /i "notification-router flutter FirebaseMessaging"
```
The `[notification-router]` line prints the resolved role/target for every tap.
