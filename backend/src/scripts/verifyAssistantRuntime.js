import { pool } from "../config/db.js";
import {
  getUserAiProfile,
  listUserAiTopics,
} from "../modules/assistant/assistant.ai.service.js";
import { getCurrentConversation } from "../modules/assistant/assistant.service.js";

const customerUserId = Number(process.argv[2]);
if (!Number.isInteger(customerUserId) || customerUserId <= 0) {
  throw new Error("Usage: node src/scripts/verifyAssistantRuntime.js <customerUserId>");
}

try {
  const [conversation, profile, topics] = await Promise.all([
    getCurrentConversation(customerUserId),
    getUserAiProfile({ customerUserId }),
    listUserAiTopics({ customerUserId, limit: 10 }),
  ]);

  console.log(
    JSON.stringify({
      ok: true,
      sessionId: Number(conversation?.sessionId || 0),
      messages: Array.isArray(conversation?.messages)
        ? conversation.messages.length
        : 0,
      profileReady: Number(profile?.profile?.user_id || 0) === customerUserId,
      topicsReady: Array.isArray(topics?.items),
    }),
  );
} finally {
  await pool.end();
}
