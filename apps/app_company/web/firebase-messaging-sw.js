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

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};
  const title = notification.title || data.title || data.notificationTitle || "Maslaki";
  const options = {
    body: notification.body || data.body || data.notificationBody || "",
    icon: data.icon || "/icons/Icon-192.png",
    badge: data.badge || "/icons/Icon-192.png",
    data,
  };
  self.registration.showNotification(title, options);
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ("focus" in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow("/");
      return undefined;
    }),
  );
});
