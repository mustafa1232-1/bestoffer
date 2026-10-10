import assert from "node:assert/strict";
import test from "node:test";

import {
  teamCodeVoiceIdentity,
  teamCodeVoicePermissions,
  teamCodeVoiceRoomName,
} from "../modules/games/team-code.voice.js";

test("team code voice names isolate rooms and authenticated users", () => {
  assert.equal(teamCodeVoiceRoomName(42), "maslaki-team-code-42");
  assert.equal(teamCodeVoiceIdentity(42, 77), "team-code:42:user:77");
  assert.notEqual(teamCodeVoiceIdentity(42, 77), teamCodeVoiceIdentity(43, 77));
});

test("cooperative team code rooms grant microphone and subscription access", () => {
  const grant = teamCodeVoicePermissions({
    id: 42,
    mode: "cooperative",
    status: "active",
  });
  assert.equal(grant.roomJoin, true);
  assert.equal(grant.canPublish, true);
  assert.equal(grant.canSubscribe, true);
  assert.equal(grant.room, "maslaki-team-code-42");
  assert.equal(grant.canPublishSources.length, 1);
});

test("solo and abandoned rooms cannot issue a team voice grant", () => {
  const solo = teamCodeVoicePermissions({ id: 1, mode: "solo", status: "active" });
  const abandoned = teamCodeVoicePermissions({
    id: 2,
    mode: "cooperative",
    status: "abandoned",
  });
  assert.equal(solo.roomJoin, false);
  assert.equal(solo.canPublish, false);
  assert.equal(abandoned.roomJoin, false);
  assert.equal(abandoned.canSubscribe, false);
});
