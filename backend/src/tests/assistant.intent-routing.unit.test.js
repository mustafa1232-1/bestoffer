import assert from "node:assert/strict";
import test from "node:test";

import {
  buildAppHelpReply,
  buildAssistantUiActions,
  detectIntent,
} from "../modules/assistant/assistant.service.js";

function targetsFor(message) {
  const intent = detectIntent(message);
  return {
    intent,
    targets: buildAssistantUiActions({
      intent,
      createdDraft: null,
      domainRecommendations: null,
    }).map((item) => item.target),
  };
}

test("assistant routes app navigation questions to their real modules", () => {
  assert.ok(targetsFor("أريد شقة للبيع في بسماية").targets.includes("real_estate"));
  assert.ok(targetsFor("افتح سوق السيارات").targets.includes("cars"));
  assert.ok(targetsFor("أحتاج صيدلية ووصفة").targets.includes("pharmacy"));
  assert.ok(targetsFor("وين ألقى الكوبونات؟").targets.includes("coupons"));
  assert.ok(targetsFor("افتح المنتجات المفضلة").targets.includes("favorites"));
  assert.ok(targetsFor("أريد تعديل عنوان محفوظ").targets.includes("addresses"));
});

test("assistant gives direct profile-name guidance and settings action", () => {
  const { intent, targets } = targetsFor("كيف أغير اسمي في التطبيق؟");

  assert.equal(intent.appHelpIntent, true);
  assert.ok(targets.includes("settings"));
  const reply = buildAppHelpReply(intent, "ar");
  assert.match(reply, /إعدادات الحساب/);
  assert.match(reply, /حفظ/);
});

test("assistant keeps taxi and services actions separate", () => {
  const taxi = targetsFor("أريد تكسي إلى الكرادة");
  assert.equal(taxi.intent.assistDomain, "taxi");
  assert.ok(taxi.targets.includes("taxi"));

  const services = targetsFor("أحتاج كهربائي لصيانة المنزل");
  assert.equal(services.intent.assistDomain, "services");
  assert.ok(services.targets.includes("services"));
});
