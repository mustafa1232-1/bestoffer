import { AccessToken, RoomServiceClient, TrackSource } from "livekit-server-sdk";

const url = String(process.env.LIVEKIT_URL || "").trim();
const apiKey = String(process.env.LIVEKIT_API_KEY || "").trim();
const apiSecret = String(process.env.LIVEKIT_API_SECRET || "").trim();
const command = String(process.argv[2] || "tokens").trim().toLowerCase();
const requestedRoom = String(process.argv[3] || "").trim();

if (!url || !apiKey || !apiSecret) {
  throw new Error("LIVEKIT_ENV_MISSING");
}

const room = requestedRoom || `maslaki-web-smoke-${Date.now()}`;
if (command !== "cleanup-all" && !/^maslaki-web-smoke-\d+$/.test(room)) {
  throw new Error("LIVEKIT_SMOKE_ROOM_INVALID");
}

if (command === "cleanup" || command === "cleanup-all") {
  const service = new RoomServiceClient(
    url.replace(/^wss:/i, "https:").replace(/^ws:/i, "http:"),
    apiKey,
    apiSecret,
  );
  const rooms = command === "cleanup-all"
    ? (await service.listRooms()).map((entry) => entry.name).filter((name) =>
      /^maslaki-web-smoke-\d+$/.test(name)
    )
    : [room];
  for (const roomName of rooms) {
    try {
      await service.deleteRoom(roomName);
    } catch (error) {
      if (!/not.?found|does not exist/i.test(String(error?.message || error))) {
        throw error;
      }
    }
  }
  console.log(JSON.stringify({ cleaned: true, rooms }));
  process.exit(0);
}

async function createToken(identity, canPublish) {
  const token = new AccessToken(apiKey, apiSecret, {
    identity,
    // WebRTC's first debug compilation can be slow on CI workstations.
    // These QA-only tokens are scoped to an isolated room that is deleted
    // immediately after the smoke test.
    ttl: 30 * 60,
  });
  token.addGrant({
    roomJoin: true,
    room,
    canSubscribe: true,
    canPublish,
    canPublishData: true,
    canPublishSources: canPublish ? [TrackSource.MICROPHONE] : [],
  });
  return token.toJwt();
}

if (command === "social-duplex") {
  console.log(JSON.stringify({
    SOCIAL_LIVEKIT_URL: url,
    SOCIAL_LIVEKIT_ROOM: room,
    SOCIAL_LIVEKIT_FIRST: await createToken("social-smoke-first", true),
    SOCIAL_LIVEKIT_SECOND: await createToken("social-smoke-second", true),
  }));
  process.exit(0);
}

console.log(
  JSON.stringify({
    url,
    room,
    publisher: await createToken("web-publisher", true),
    subscriber: await createToken("web-subscriber", false),
  }),
);
