import assert from "node:assert/strict";
import test from "node:test";

import {
  __realtimeGatewayTestApi,
  emitRealtimeToUser,
} from "../shared/realtime/realtime-gateway.js";

test.beforeEach(() => {
  __realtimeGatewayTestApi.reset();
});

test("gateway keeps SSE path working in sse_only mode", async () => {
  const sseCalls = [];
  const publishCalls = [];

  __realtimeGatewayTestApi.setModeResolver(() => "sse_only");
  __realtimeGatewayTestApi.setAllocateId(() => 7001);
  __realtimeGatewayTestApi.setSseEmitter((userId, event, data, options) => {
    sseCalls.push({ userId, event, data, options });
  });
  __realtimeGatewayTestApi.setPublisher(async (...args) => {
    publishCalls.push(args);
  });

  const eventId = await emitRealtimeToUser(12, "notification", {
    notification: { id: 5 },
  });

  assert.equal(eventId, 7001);
  assert.equal(sseCalls.length, 1);
  assert.equal(sseCalls[0].options.id, 7001);
  assert.equal(publishCalls.length, 0);
});

test("gateway maps notification, social, and taxi events to expected topics", async () => {
  const topics = [];

  __realtimeGatewayTestApi.setModeResolver(() => "dual");
  __realtimeGatewayTestApi.setAllocateId(() => 8800);
  __realtimeGatewayTestApi.setSseEmitter(() => {});
  __realtimeGatewayTestApi.setPublisher(async (topic) => {
    topics.push(topic);
  });
  __realtimeGatewayTestApi.setMembershipSyncers({
    syncChatThreadMembers: async () => ({ ok: true }),
    syncTaxiRideMembers: async () => ({ ok: true }),
    syncOrderMembers: async () => ({ ok: true }),
  });

  await emitRealtimeToUser(9, "notification", {
    notification: {
      id: 1,
      order_id: 55,
      payload: { orderId: 55, status: "accepted" },
    },
  });
  await emitRealtimeToUser(9, "social_chat_message", {
    threadId: 33,
    message: { id: 44, threadId: 33, senderUserId: 9, body: "hi" },
  });
  await emitRealtimeToUser(9, "taxi_ride_update", {
    rideId: 77,
    ride: { id: 77, status: "searching" },
  });

  assert.deepEqual(topics, [
    "notifications:user:9",
    "order:55",
    "social:user:9",
    "chat:thread:33",
    "taxi:user:9",
    "taxi:ride:77",
  ]);
});

test("gateway queues outbox when supabase publish fails", async () => {
  const queued = [];
  const sseCalls = [];

  __realtimeGatewayTestApi.setModeResolver(() => "dual");
  __realtimeGatewayTestApi.setAllocateId(() => 9911);
  __realtimeGatewayTestApi.setSseEmitter((userId) => {
    sseCalls.push(userId);
  });
  __realtimeGatewayTestApi.setPublisher(async () => {
    throw new Error("broadcast failed");
  });
  __realtimeGatewayTestApi.setOutboxEnqueuer(async (entry) => {
    queued.push(entry);
    return 1;
  });
  __realtimeGatewayTestApi.setMembershipSyncers({
    syncChatThreadMembers: async () => ({ ok: true }),
    syncTaxiRideMembers: async () => ({ ok: true }),
    syncOrderMembers: async () => ({ ok: true }),
  });

  await emitRealtimeToUser(18, "notification", {
    notification: { id: 4, payload: { orderId: 12 } },
  });

  assert.equal(sseCalls.length, 1);
  assert.equal(queued.length >= 1, true);
  assert.equal(queued[0].topic, "notifications:user:18");
});

test("gateway skips shared topics when membership sync is unavailable", async () => {
  const topics = [];

  __realtimeGatewayTestApi.setModeResolver(() => "dual");
  __realtimeGatewayTestApi.setAllocateId(() => 4100);
  __realtimeGatewayTestApi.setSseEmitter(() => {});
  __realtimeGatewayTestApi.setPublisher(async (topic) => {
    topics.push(topic);
  });
  __realtimeGatewayTestApi.setMembershipSyncers({
    syncChatThreadMembers: async () => ({ ok: false, reason: "missing_sql_objects" }),
    syncTaxiRideMembers: async () => ({ ok: false, reason: "missing_sql_objects" }),
    syncOrderMembers: async () => ({ ok: false, reason: "missing_sql_objects" }),
  });

  await emitRealtimeToUser(9, "social_chat_message", {
    threadId: 33,
    message: { id: 44, threadId: 33, senderUserId: 9, body: "hi" },
  });
  await emitRealtimeToUser(9, "taxi_ride_update", {
    rideId: 77,
    ride: { id: 77, status: "searching" },
  });
  await emitRealtimeToUser(9, "order_tracking_update", {
    orderId: 55,
    stage: "heading_to_customer",
  });

  assert.deepEqual(topics, [
    "social:user:9",
    "taxi:user:9",
    "user:9",
  ]);
});
