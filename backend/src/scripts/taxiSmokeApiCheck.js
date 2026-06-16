/* eslint-disable no-console */
import "dotenv/config";

const baseUrl = (
  process.env.API_BASE_URL ||
  process.env.E2E_BASE_URL ||
  "http://127.0.0.1:3000"
).replace(/\/+$/, "");

async function request(path, { method = "GET", token = null, body = null } = {}) {
  const headers = {
    "Content-Type": "application/json",
    "Cache-Control": "no-cache",
    Pragma: "no-cache",
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });

  const text = await res.text();
  let payload = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch {
      payload = text;
    }
  }
  return { status: res.status, payload };
}

async function loginWith(rolePrefix) {
  const phone = String(process.env[`${rolePrefix}_PHONE`] || "").trim();
  const pin = String(process.env[`${rolePrefix}_PIN`] || "").trim();
  if (!phone || !pin) {
    throw new Error(`missing credentials for ${rolePrefix}`);
  }
  const out = await request("/api/auth/login", {
    method: "POST",
    body: { phone, pin },
  });
  if (out.status !== 200 || !out.payload?.token) {
    throw new Error(`login failed for ${rolePrefix} (status=${out.status})`);
  }
  return String(out.payload.token);
}

function extractRide(payload) {
  if (payload?.ride?.ride?.id) return payload.ride.ride;
  if (payload?.ride?.id) return payload.ride;
  if (payload?.id) return payload;
  return null;
}

async function run() {
  if (!baseUrl) throw new Error("API base url missing");
  console.log(`[taxi-smoke] base_url=${baseUrl}`);

  const customerToken = await loginWith("ROLE_USER");
  const captainToken = await loginWith("ROLE_DELIVERY");

  const currentBefore = await request("/api/taxi/rides/current", { token: customerToken });
  const activeBeforeRide = currentBefore.status === 200 ? extractRide(currentBefore.payload) : null;
  if (activeBeforeRide?.id) {
    await request(`/api/taxi/rides/${activeBeforeRide.id}/cancel`, {
      method: "POST",
      token: customerToken,
    });
  }

  const presence = await request("/api/taxi/captain/presence", {
    method: "POST",
    token: captainToken,
    body: {
      isOnline: true,
      latitude: 33.31456,
      longitude: 44.36611,
      headingDeg: 90,
      speedKmh: 0,
      accuracyM: 6,
      radiusM: 4000,
    },
  });
  if (presence.status !== 200) {
    throw new Error(`captain presence failed (status=${presence.status})`);
  }

  const now = Date.now();
  const create = await request("/api/taxi/rides", {
    method: "POST",
    token: customerToken,
    body: {
      pickupLatitude: 33.31456,
      pickupLongitude: 44.36611,
      dropoffLatitude: 33.32091,
      dropoffLongitude: 44.39118,
      pickupLabel: `Taxi smoke pickup ${now}`,
      dropoffLabel: `Taxi smoke dropoff ${now}`,
      proposedFareIqd: 12000,
      searchRadiusM: 3000,
      note: `taxi-smoke-${now}`,
    },
  });
  if (create.status !== 201) {
    throw new Error(
      `create ride failed (status=${create.status}, body=${JSON.stringify(create.payload)})`
    );
  }
  const rideId = Number(create.payload?.ride?.id || create.payload?.id || 0);
  if (!rideId) throw new Error("create ride missing ride id");

  const nearby = await request("/api/taxi/captain/nearby-requests?radiusM=4000&limit=20", {
    token: captainToken,
  });
  if (nearby.status !== 200) {
    throw new Error(`nearby requests failed (status=${nearby.status})`);
  }
  const hasRide =
    Array.isArray(nearby.payload?.items) &&
    nearby.payload.items.some((item) => Number(item?.id || 0) === rideId);
  if (!hasRide) {
    throw new Error("new ride not visible in captain nearby list");
  }

  const decline = await request(`/api/taxi/rides/${rideId}/decline`, {
    method: "POST",
    token: captainToken,
  });
  if (decline.status !== 200) {
    throw new Error(`decline failed (status=${decline.status})`);
  }

  const current = await request("/api/taxi/rides/current", { token: customerToken });
  if (current.status !== 200) {
    throw new Error(`customer current ride failed (status=${current.status})`);
  }
  const currentRide = extractRide(current.payload);

  const cancel = await request(`/api/taxi/rides/${rideId}/cancel`, {
    method: "POST",
    token: customerToken,
  });
  if (cancel.status !== 200) {
    throw new Error(`cancel failed (status=${cancel.status})`);
  }

  console.log(
    `[taxi-smoke] PASS rideId=${rideId} rejectedCaptainsCount=${Number(
      decline.payload?.rejectedCaptainsCount || 0
    )} priceRaiseRecommended=${Boolean(currentRide?.priceRaiseRecommended)}`
  );
}

run().catch((error) => {
  console.error(`[taxi-smoke] FAIL ${error?.message || error}`);
  process.exitCode = 1;
});
