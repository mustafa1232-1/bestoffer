import { randomInt, randomUUID } from "node:crypto";
import test from "node:test";

import { app } from "../app.js";
import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import {
  assertStatus,
  createActor,
  request,
  startLocalServer,
  stopLocalServer,
} from "../scripts/e2eTestUtils.js";

function makePhone() {
  return `077${String(randomInt(0, 10_000_000)).padStart(8, "0")}`;
}

function makeUsername() {
  return `search_${randomUUID().replace(/-/g, "").slice(0, 10)}`.slice(0, 24);
}

async function createCustomer() {
  return createUser({
    fullName: `Search Customer ${randomUUID().slice(0, 8)}`,
    username: makeUsername(),
    phone: makePhone(),
    pinHash: await hashPin("1234"),
    block: "A1",
    buildingNumber: "1",
    apartment: "1",
    role: "user",
    analyticsConsentGranted: true,
    analyticsConsentVersion: "commerce_search_alias_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
  });
}

test("commerce product search is mounted at canonical and legacy paths", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `commerce-search-route-${Date.now().toString(36)}`;
  const actor = createActor("customer", runTag);
  actor.appFlavor = "user";
  let customer = null;

  try {
    customer = await createCustomer();
    const login = await request(baseUrl, actor, "POST", "/api/auth/login", {
      phone: customer.phone,
      pin: "1234",
    });
    assertStatus(login, 200, "customer login");
    actor.token = String(login.data?.token || "");

    const canonical = await request(
      baseUrl,
      actor,
      "GET",
      "/api/commerce/search/products",
    );
    assertStatus(canonical, 400, "canonical commerce product search route");

    const legacy = await request(baseUrl, actor, "GET", "/api/search/products");
    assertStatus(legacy, 400, "legacy commerce product search route");

    const search = await request(
      baseUrl,
      actor,
      "GET",
      "/api/commerce/search/products?q=definitely-no-product-match",
    );
    assertStatus(search, 200, "canonical commerce product search query");
  } finally {
    if (customer?.id) {
      await q(`DELETE FROM user_session WHERE user_id=$1`, [
        Number(customer.id),
      ]).catch(() => {});
      await q(`DELETE FROM app_user WHERE id=$1`, [Number(customer.id)]).catch(
        () => {},
      );
    }
    await stopLocalServer(server);
  }
});
