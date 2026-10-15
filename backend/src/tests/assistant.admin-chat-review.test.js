import assert from "node:assert/strict";
import { randomInt, randomUUID } from "node:crypto";
import test from "node:test";

import { q } from "../config/db.js";
import {
  listAiChatMessagesForAdmin,
  listAiChatSessionsForUserForAdmin,
  listAiChatUsersForAdmin,
} from "../modules/assistant/assistant.ai.service.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";

function makePhone() {
  return `078${String(randomInt(0, 100_000_000)).padStart(8, "0")}`;
}

async function createCustomer(label) {
  const suffix = randomUUID().replaceAll("-", "").slice(0, 8);
  return createUser({
    fullName: `AI Review ${label} ${suffix}`,
    username: `ai_${label}_${suffix}`.slice(0, 24),
    phone: makePhone(),
    pinHash: await hashPin("199711"),
    block: "A1",
    buildingNumber: "1",
    apartment: "1",
    role: "user",
  });
}

test("admin AI chat review groups users, sessions, and messages with consent", async () => {
  const visibleUser = await createCustomer("visible");
  const hiddenUser = await createCustomer("hidden");
  const userIds = [Number(visibleUser.id), Number(hiddenUser.id)];

  try {
    await q(
      `UPDATE app_user
       SET ai_chat_review_consent = CASE WHEN id = $1 THEN TRUE ELSE FALSE END
       WHERE id = ANY($2::bigint[])`,
      [Number(visibleUser.id), userIds],
    );

    const firstSession = await q(
      `INSERT INTO ai_chat_session (customer_user_id, title, last_message_at)
       VALUES ($1, $2, NOW() - INTERVAL '2 minutes')
       RETURNING id`,
      [Number(visibleUser.id), "طلب مطعم"],
    );
    const secondSession = await q(
      `INSERT INTO ai_chat_session (customer_user_id, title, last_message_at)
       VALUES ($1, $2, NOW())
       RETURNING id`,
      [Number(visibleUser.id), "حجز تكسي"],
    );
    const hiddenSession = await q(
      `INSERT INTO ai_chat_session (customer_user_id, title)
       VALUES ($1, $2)
       RETURNING id`,
      [Number(hiddenUser.id), "محادثة مخفية"],
    );

    await q(
      `INSERT INTO ai_chat_message (session_id, role, text)
       VALUES
         ($1, 'user', 'أريد مطعماً'),
         ($1, 'assistant', 'هذه الخيارات المتاحة'),
         ($2, 'user', 'أريد تكسي إلى الكرادة'),
         ($2, 'assistant', 'افتح التكسي وحدد الوجهة'),
         ($3, 'user', 'لا تعرض هذه المحادثة')`,
      [
        Number(firstSession.rows[0].id),
        Number(secondSession.rows[0].id),
        Number(hiddenSession.rows[0].id),
      ],
    );

    const users = await listAiChatUsersForAdmin({
      search: visibleUser.phone,
      limit: 20,
    });
    assert.equal(users.total, 1);
    assert.equal(users.items.length, 1);
    assert.equal(Number(users.items[0].customer_user_id), Number(visibleUser.id));
    assert.equal(Number(users.items[0].sessions_count), 2);
    assert.equal(Number(users.items[0].messages_count), 4);

    const sessions = await listAiChatSessionsForUserForAdmin(
      visibleUser.id,
      { limit: 20 },
    );
    assert.equal(sessions.total, 2);
    assert.equal(sessions.items[0].title, "حجز تكسي");
    assert.equal(Number(sessions.items[0].messages_count), 2);

    const messages = await listAiChatMessagesForAdmin(
      secondSession.rows[0].id,
      { limit: 20 },
    );
    assert.equal(messages.items.length, 2);
    assert.equal(messages.items[0].role, "assistant");
    assert.equal(messages.items[1].role, "user");

    const hiddenSearch = await listAiChatUsersForAdmin({
      search: hiddenUser.phone,
      limit: 20,
    });
    assert.equal(hiddenSearch.total, 0);
    assert.deepEqual(hiddenSearch.items, []);

    await q(
      `UPDATE app_user
       SET ai_chat_review_consent = FALSE
       WHERE id = $1`,
      [Number(visibleUser.id)],
    );
    const afterOptOut = await listAiChatUsersForAdmin({
      search: visibleUser.phone,
      limit: 20,
    });
    assert.equal(afterOptOut.total, 0);
  } finally {
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});
