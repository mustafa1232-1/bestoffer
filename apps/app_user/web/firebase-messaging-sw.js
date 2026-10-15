importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyBwUhhCl-MONjtOl8oddvmwvqZUFEvQ5M8",
  appId: "1:1016190459986:web:f8aa889b7a8a354e117f8b",
  messagingSenderId: "1016190459986",
  projectId: "maslaki-61a97",
  authDomain: "maslaki-61a97.firebaseapp.com",
  storageBucket: "maslaki-61a97.firebasestorage.app",
  measurementId: "G-MYS8SC0PJ5",
});

const messaging = firebase.messaging();

function isActionRequired(data, notification) {
  return (
    data.requiresAction === "true" ||
    data.actionable === "true" ||
    Boolean(data.urgentChannelId) ||
    /call|urgent|new_order|courier|delivery_order_ready|delivery_order_cancelled|taxi_ride|taxi_trips_new|request_cancel/i.test(
      `${data.type || ""} ${data.target || ""} ${data.targetModule || ""} ${notification.title || ""}`,
    )
  );
}

function encodePayloadForOpenWindow(payload) {
  try {
    const json = JSON.stringify(payload || {});
    const bytes = new TextEncoder().encode(json);
    let binary = "";
    bytes.forEach((byte) => {
      binary += String.fromCharCode(byte);
    });
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  } catch (_) {
    return "";
  }
}

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};
  const requiresAction = isActionRequired(data, notification);
  const rawTitle = notification.title || data.title || data.notificationTitle || "Maslaki";
  const title =
    requiresAction && !/مهم|عاجل|urgent|important/i.test(rawTitle)
      ? `تنبيه مهم: ${rawTitle}`
      : rawTitle;
  const options = {
    body: notification.body || data.body || data.notificationBody || "",
    icon: data.icon || "/icons/Icon-192.png",
    badge: data.badge || "/icons/Icon-192.png",
    dir: "rtl",
    lang: "ar",
    tag:
      data.notificationId ||
      data.eventId ||
      data.orderId ||
      data.rideId ||
      data.type ||
      "maslaki",
    renotify: Boolean(requiresAction),
    requireInteraction: Boolean(requiresAction),
    silent: false,
    vibrate: requiresAction ? [0, 700, 250, 700, 250, 900] : [0, 180, 80, 180],
    actions: requiresAction
      ? [
          {
            action: "open",
            title: "فتح الآن",
          },
        ]
      : [],
    data,
  };
  self.registration.showNotification(title, options);
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const payload = event.notification.data || {};
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ("focus" in client) {
          client.postMessage({
            type: "maslaki_notification_click",
            payload,
          });
          return client.focus();
        }
      }
      if (clients.openWindow) {
        const encoded = encodePayloadForOpenWindow(payload);
        const url = encoded ? `/?notificationPayload=${encoded}` : "/";
        return clients.openWindow(url);
      }
      return undefined;
    }),
  );
});
