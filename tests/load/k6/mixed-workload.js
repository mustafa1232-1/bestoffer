import http from "k6/http";
import { check, sleep } from "k6";

function parseJsonEnv(name, fallback) {
  const raw = (__ENV[name] || "").trim();
  if (!raw) return fallback;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return fallback;
  }
}

function parseJsonFile(path, fallback) {
  const rawPath = String(path || "").trim();
  if (!rawPath) return fallback;
  try {
    return JSON.parse(open(rawPath));
  } catch (_) {
    return fallback;
  }
}

function toInt(value, fallback) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function scenarioVus(total, percent, fallback = 1) {
  const value = Math.floor((total * percent) / 100);
  return Math.max(fallback, value);
}

const TOTAL_VUS = toInt(__ENV.TOTAL_VUS, 25);
const DURATION = (__ENV.DURATION || "45s").trim();
const BASE_URL = (__ENV.BASE_URL || "https://bestoffer-production.up.railway.app")
  .trim()
  .replace(/\/+$/, "");
const RUN_TAG = (__ENV.RUN_TAG || "k6-load").trim();
const MERCHANT_ID = Number(__ENV.MERCHANT_ID || 0) || 0;
const PRODUCT_ID = Number(__ENV.PRODUCT_ID || 0) || 0;
const PHARMACY_MERCHANT_ID = Number(__ENV.PHARMACY_MERCHANT_ID || 0) || 0;
const PHARMACY_PRODUCT_ID = Number(__ENV.PHARMACY_PRODUCT_ID || 0) || 0;
const AUTH_TOKENS = (
  parseJsonFile(__ENV.AUTH_TOKENS_FILE, null) ??
  parseJsonEnv("AUTH_TOKENS_JSON", [])
).filter(
  (item) => typeof item?.token === "string" && item.token.trim().length > 0
);
const AUTH_POOL_SIZE = AUTH_TOKENS.length;
const BULK_STAGE = TOTAL_VUS >= 250;
const HYPER_BULK_STAGE = TOTAL_VUS >= 1000;

const BROWSE_THINK_TIME = HYPER_BULK_STAGE ? 20 : BULK_STAGE ? 6 : 1;
const MESSAGES_THINK_TIME = HYPER_BULK_STAGE ? 3.5 : BULK_STAGE ? 2 : 1;
const PASSIVE_SOCIAL_THINK_TIME = HYPER_BULK_STAGE ? 4 : BULK_STAGE ? 2 : 1;
const PASSIVE_PHARMACY_THINK_TIME = HYPER_BULK_STAGE ? 4 : BULK_STAGE ? 2 : 1;

function capVus(weighted, cap, fallback = 1) {
  return Math.max(fallback, Math.min(weighted, cap));
}

const weightedShoppingVus = scenarioVus(TOTAL_VUS, 20);
const weightedTaxiVus = scenarioVus(TOTAL_VUS, 15);
const weightedSocialVus = scenarioVus(TOTAL_VUS, 15);
const weightedPharmacyVus = scenarioVus(TOTAL_VUS, 5);
const weightedMessagesVus = scenarioVus(TOTAL_VUS, 10);

const shoppingCap = BULK_STAGE ? 20 : 200;
const taxiCap = BULK_STAGE ? 30 : 100;
const socialCap = BULK_STAGE ? 20 : 200;
const pharmacyCap = BULK_STAGE ? 8 : 50;
const messagesCap = BULK_STAGE ? 40 : 200;

const shoppingVus = capVus(weightedShoppingVus, Math.max(5, Math.min(AUTH_POOL_SIZE || 5, shoppingCap)));
const taxiVus = capVus(weightedTaxiVus, Math.max(3, Math.min(Math.floor((AUTH_POOL_SIZE || 6) / 2), taxiCap)));
const socialVus = capVus(weightedSocialVus, Math.max(5, Math.min(AUTH_POOL_SIZE || 5, socialCap)));
const pharmacyVus = capVus(weightedPharmacyVus, Math.max(1, Math.min(Math.floor((AUTH_POOL_SIZE || 4) / 4), pharmacyCap)));
const messagesVus = capVus(weightedMessagesVus, Math.max(2, Math.min(AUTH_POOL_SIZE || 2, messagesCap)));
const browseVus = Math.max(
  1,
  TOTAL_VUS - (shoppingVus + taxiVus + socialVus + pharmacyVus + messagesVus)
);

function currentAuthContext() {
  if (!AUTH_TOKENS.length) return null;
  const index = ((__VU - 1) % AUTH_TOKENS.length + AUTH_TOKENS.length) % AUTH_TOKENS.length;
  return AUTH_TOKENS[index];
}

export const options = {
  scenarios: {
    browse: {
      executor: "constant-vus",
      vus: browseVus,
      duration: DURATION,
      exec: "browseHome",
    },
    shopping: {
      executor: "constant-vus",
      vus: shoppingVus,
      duration: DURATION,
      exec: "shoppingFlow",
      startTime: "2s",
    },
    taxi: {
      executor: "constant-vus",
      vus: taxiVus,
      duration: DURATION,
      exec: "taxiFlow",
      startTime: "4s",
    },
    social: {
      executor: "constant-vus",
      vus: socialVus,
      duration: DURATION,
      exec: "socialFlow",
      startTime: "6s",
    },
    pharmacy: {
      executor: "constant-vus",
      vus: pharmacyVus,
      duration: DURATION,
      exec: "pharmacyFlow",
      startTime: "8s",
    },
    messages: {
      executor: "constant-vus",
      vus: messagesVus,
      duration: DURATION,
      exec: "messagesFlow",
      startTime: "10s",
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.08"],
    http_req_duration: ["p(95)<2500", "p(99)<6000"],
  },
};

function authHeaders() {
  const auth = currentAuthContext();
  if (!auth) return {};
  return {
    Authorization: `Bearer ${auth.token}`,
    "X-Device-Id": auth.deviceId || `k6-device-${__VU}`,
    "X-Client-Platform": auth.platform || "k6",
    "X-App-Version": auth.appVersion || "k6-load/1",
    "X-Device-Model": auth.model || "k6-runner",
    "User-Agent": auth.userAgent || `k6-load/1/vu-${__VU}`,
    "Content-Type": "application/json",
  };
}

function publicClientHeaders() {
  return {
    "X-Device-Id": `k6-public-device-${__VU}`,
    "X-Client-Platform": "k6-public",
    "X-App-Version": "k6-load/1",
    "X-Device-Model": "k6-public-runner",
    "User-Agent": `k6-public/1/vu-${__VU}`,
  };
}

function getJson(path, params = {}) {
  return http.get(`${BASE_URL}${path}`, params);
}

function postJson(path, body, params = {}) {
  return http.post(`${BASE_URL}${path}`, JSON.stringify(body), {
    ...params,
    headers: {
      ...authHeaders(),
      ...(params.headers || {}),
    },
  });
}

function parseBody(res) {
  try {
    return res.json();
  } catch (_) {
    return null;
  }
}

function resolveRideId(payload) {
  return Number(payload?.ride?.id || payload?.id || 0);
}

function cancelCurrentRideIfAny() {
  const headers = authHeaders();
  const currentRes = getJson("/api/taxi/rides/current", { headers });
  if (currentRes.status !== 200) return null;
  const current = parseBody(currentRes);
  const rideId = resolveRideId(current);
  if (rideId <= 0) return null;
  const cancelRes = postJson(`/api/taxi/rides/${rideId}/cancel`, {});
  return { rideId, cancelRes };
}

export function browseHome() {
  const headers = authHeaders();
  const publicHeaders = publicClientHeaders();
  if (HYPER_BULK_STAGE) {
    const bulkRoll = Math.random();
    if (bulkRoll < 0.3) {
      const merchantRes = getJson("/api/merchants", {
        headers: publicHeaders,
      });
      check(merchantRes, { "merchants browse ok": (r) => r.status === 200 });
    } else if (bulkRoll < 0.55) {
      const merchantRes = getJson("/api/merchants?type=restaurant", {
        headers: publicHeaders,
      });
      check(merchantRes, { "merchants browse ok": (r) => r.status === 200 });
    } else if (bulkRoll < 0.8 && MERCHANT_ID) {
      const merchantProductsRes = getJson(`/api/merchants/${MERCHANT_ID}/products`, {
        headers: publicHeaders,
      });
      check(merchantProductsRes, {
        "merchant products ok": (r) => r.status === 200,
      });
    } else if (MERCHANT_ID) {
      getJson(`/api/merchants/${MERCHANT_ID}`, {
        headers: publicHeaders,
      });
    } else {
      const merchantRes = getJson("/api/merchants", {
        headers: publicHeaders,
      });
      check(merchantRes, { "merchants browse ok": (r) => r.status === 200 });
    }

    sleep(BROWSE_THINK_TIME);
    return;
  }

  const browseRoll = Math.random();
  if (browseRoll < 0.2) {
    const merchantRes = getJson("/api/merchants", {
      headers: publicHeaders,
    });
    check(merchantRes, { "merchants browse ok": (r) => r.status === 200 });
  } else if (browseRoll < 0.3) {
    const merchantRes = getJson("/api/merchants?type=restaurant", {
      headers: publicHeaders,
    });
    check(merchantRes, { "merchants browse ok": (r) => r.status === 200 });
  } else if (browseRoll < 0.55) {
    getJson("/api/feed/explore", { headers });
  } else if (browseRoll < 0.8) {
    getJson("/api/feed/reels/explore?limit=12", { headers });
  } else if (browseRoll < 0.9) {
    getJson("/api/orders/my", { headers });
  } else {
    getJson("/api/notifications/unread-count", { headers });
  }

  sleep(BROWSE_THINK_TIME);
}

export function shoppingFlow() {
  if (!MERCHANT_ID || !PRODUCT_ID) {
    browseHome();
    return;
  }
  if (HYPER_BULK_STAGE) {
    const merchantRes = getJson(`/api/merchants/${MERCHANT_ID}/products`, {
      headers: publicClientHeaders(),
    });
    check(merchantRes, { "merchant products ok": (r) => r.status === 200 });
    if (__ITER % 5 === 0) {
      getJson("/api/orders/my", { headers: authHeaders() });
    }
    sleep(2);
    return;
  }
  const headers = authHeaders();
  const merchantRes = getJson(`/api/merchants/${MERCHANT_ID}/products`, {
    headers: publicClientHeaders(),
  });
  check(merchantRes, { "merchant products ok": (r) => r.status === 200 });

  if (BULK_STAGE && __ITER % (HYPER_BULK_STAGE ? 15 : 5) !== 0) {
    sleep(HYPER_BULK_STAGE ? 2 : 1.5);
    return;
  }

  const orderRes = postJson("/api/orders", {
    merchantId: MERCHANT_ID,
    items: [{ productId: PRODUCT_ID, quantity: 1 }],
    note: `k6-order-${RUN_TAG}-${__VU}-${__ITER}`,
  });
  check(orderRes, { "order create ok": (r) => r.status === 201 || r.status === 200 });
  getJson("/api/orders/my", { headers });
  sleep(1);
}

export function taxiFlow() {
  if (HYPER_BULK_STAGE && __ITER % 3 !== 0) {
    getJson("/api/taxi/rides/current", { headers: authHeaders() });
    sleep(1.5);
    return;
  }

  const taxiCreateParams = {
    responseCallback: http.expectedStatuses(200, 201, 409),
  };

  let rideRes = postJson("/api/taxi/rides", {
    pickupLatitude: 33.2977,
    pickupLongitude: 44.3922,
    dropoffLatitude: 33.3152,
    dropoffLongitude: 44.3661,
    pickupLabel: `k6-pickup-${RUN_TAG}`,
    dropoffLabel: `k6-dropoff-${RUN_TAG}`,
    proposedFareIqd: 7000,
    searchRadiusM: 3000,
  }, taxiCreateParams);
  if (rideRes.status === 409) {
    cancelCurrentRideIfAny();
    sleep(0.25);
    rideRes = postJson("/api/taxi/rides", {
      pickupLatitude: 33.2977,
      pickupLongitude: 44.3922,
      dropoffLatitude: 33.3152,
      dropoffLongitude: 44.3661,
      pickupLabel: `k6-pickup-${RUN_TAG}`,
      dropoffLabel: `k6-dropoff-${RUN_TAG}`,
      proposedFareIqd: 7000,
      searchRadiusM: 3000,
    }, taxiCreateParams);
  }
  const rideCreateHandled =
    rideRes.status === 201 || rideRes.status === 200 || rideRes.status === 409;
  check(rideRes, { "taxi create ok": () => rideCreateHandled });
  const ride = parseBody(rideRes);
  const rideId = resolveRideId(ride);
  if (rideId > 0) {
    const cancelRes = postJson(`/api/taxi/rides/${rideId}/cancel`, {});
    check(cancelRes, { "taxi cancel ok": (r) => r.status === 200 || r.status === 204 });
  }
  sleep(1);
}

export function socialFlow() {
  if (BULK_STAGE && __ITER % (HYPER_BULK_STAGE ? 8 : 4) !== 0) {
    getJson("/api/feed/explore", { headers: authHeaders() });
    sleep(PASSIVE_SOCIAL_THINK_TIME);
    return;
  }

  const postRes = postJson("/api/feed/posts", {
    caption: `k6-social-${RUN_TAG}-${__VU}-${__ITER}`,
    postKind: "text",
  });
  check(postRes, { "social post ok": (r) => r.status === 201 || r.status === 200 });
  const post = parseBody(postRes);
  const postId = Number(post?.post?.id || 0);
  if (postId > 0) {
    const likeRes = postJson(`/api/feed/posts/${postId}/like`, {});
    check(likeRes, { "social like ok": (r) => r.status === 200 || r.status === 201 });
    const commentRes = postJson(`/api/feed/posts/${postId}/comments`, {
      body: `k6-comment-${RUN_TAG}-${__VU}-${__ITER}`,
    });
    check(commentRes, { "social comment ok": (r) => r.status === 200 || r.status === 201 });
  }
  sleep(1);
}

export function pharmacyFlow() {
  if (!PHARMACY_MERCHANT_ID) {
    browseHome();
    return;
  }
  if (BULK_STAGE && __ITER % (HYPER_BULK_STAGE ? 8 : 4) !== 0) {
    getJson("/api/pharmacy/conversations", { headers: authHeaders() });
    sleep(PASSIVE_PHARMACY_THINK_TIME);
    return;
  }
  const convoRes = postJson("/api/pharmacy/conversations", {
    merchantId: PHARMACY_MERCHANT_ID,
    initialMessage: `k6-pharmacy-${RUN_TAG}-${__VU}-${__ITER}`,
    metadata: {
      productId: PHARMACY_PRODUCT_ID || null,
      source: "k6",
    },
  });
  check(convoRes, { "pharmacy conversation ok": (r) => r.status === 201 || r.status === 200 });
  const convo = parseBody(convoRes);
  const conversationId = Number(convo?.conversation?.id || 0);
  if (conversationId > 0) {
    const msgRes = postJson(`/api/pharmacy/conversations/${conversationId}/messages`, {
      message: `k6-message-${RUN_TAG}-${__VU}-${__ITER}`,
    });
    check(msgRes, { "pharmacy message ok": (r) => r.status === 201 || r.status === 200 });
  }
  sleep(1);
}

export function messagesFlow() {
  const res = getJson("/api/feed/chats/threads", { headers: authHeaders() });
  check(res, { "chat threads ok": (r) => r.status === 200 });
  sleep(MESSAGES_THINK_TIME);
}
