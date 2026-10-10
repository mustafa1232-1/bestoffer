import assert from "node:assert/strict";
import test from "node:test";

import {
  buildMafiaRoleDeck,
  mafiaActionsForRole,
  mafiaNarratorCue,
  mafiaPhaseSeconds,
  tallyMafiaBallots,
  teamForMafiaRole,
} from "../modules/games/mafia.service.js";
import { mafiaVoicePermissions } from "../modules/games/mafia.voice.js";
import {
  createMafiaBody,
  mafiaReportBody,
} from "../modules/games/games.validators.js";

test("mafia role decks stay balanced from 7 through 14 players", () => {
  for (let count = 7; count <= 14; count += 1) {
    const deck = buildMafiaRoleDeck(count, "standard");
    const mafiaCount = deck.filter((role) => teamForMafiaRole(role) === "mafia").length;
    assert.equal(deck.length, count);
    assert.equal(new Set(deck).has("detective"), true);
    assert.equal(new Set(deck).has("doctor"), true);
    assert.equal(mafiaCount, count <= 9 ? 2 : count <= 13 ? 3 : 4);
    assert.equal(mafiaCount < count - mafiaCount, true);
  }
});

test("advanced 14-player deck adds specialists without changing team balance", () => {
  const deck = buildMafiaRoleDeck(14, "advanced");
  assert.equal(deck.filter((role) => teamForMafiaRole(role) === "mafia").length, 4);
  assert.equal(deck.includes("don"), true);
  assert.equal(deck.includes("framer"), true);
  assert.equal(deck.includes("bodyguard"), true);
});

test("every specialist exposes only its legal night actions", () => {
  assert.deepEqual(mafiaActionsForRole("framer"), ["mafia_kill", "framer_frame"]);
  assert.deepEqual(mafiaActionsForRole("don"), ["mafia_kill", "don_inspect"]);
  assert.deepEqual(mafiaActionsForRole("bodyguard"), ["bodyguard_protect"]);
  assert.deepEqual(mafiaActionsForRole("doctor"), ["doctor_protect"]);
  assert.deepEqual(mafiaActionsForRole("citizen"), []);
});

test("ballot tally ignores abstentions and reports exact ties", () => {
  const tally = tallyMafiaBallots([
    { target_player_id: 3 },
    { target_player_id: 4 },
    { target_player_id: 3 },
    { target_player_id: 4 },
    { target_player_id: null },
    { target_player_id: 99 },
  ], [3, 4]);
  assert.deepEqual(tally.winners, [3, 4]);
  assert.equal(tally.topVotes, 2);
});

test("the unique highest vote wins even without an absolute majority", () => {
  const tally = tallyMafiaBallots([
    { target_player_id: 1 },
    { target_player_id: 1 },
    { target_player_id: 5 },
    { target_player_id: null },
  ], [1, 5]);
  assert.deepEqual(tally.winners, [1]);
  assert.equal(tally.topVotes, 2);
});

test("quick rooms shorten every timed phase without changing classic rooms", () => {
  const classic = { settings: { pace: "classic" } };
  const quick = { settings: { pace: "quick" } };
  assert.equal(mafiaPhaseSeconds(classic, "day_discussion"), 180);
  assert.equal(mafiaPhaseSeconds(quick, "day_discussion"), 90);
  assert.equal(mafiaPhaseSeconds(quick, "night"), 30);
  assert.equal(mafiaPhaseSeconds(quick, "lobby"), null);
});

test("narrator cues are stable per phase and prioritize elimination events", () => {
  const room = { status: "night", phase_version: 4 };
  const phaseCue = mafiaNarratorCue(room);
  assert.equal(phaseCue.id, "phase-4-night");
  assert.equal(phaseCue.tone, "mystery");
  const eliminationCue = mafiaNarratorCue(room, {
    id: 91,
    event_type: "player_eliminated",
  });
  assert.equal(eliminationCue.id, "elimination-91");
  assert.equal(eliminationCue.tone, "danger");
});

test("room cosmetics and private reports accept only bounded known values", () => {
  assert.equal(createMafiaBody({ tableTheme: "cinema" }).tableTheme, "cinema");
  assert.equal(createMafiaBody({ tableTheme: "unknown" }).tableTheme, "emerald");
  assert.deepEqual(
    mafiaReportBody({
      targetPlayerId: 7,
      commandId: "report-12345678",
      reason: "inappropriate_audio",
      details: "audio abuse",
    }),
    {
      targetPlayerId: 7,
      commandId: "report-12345678",
      reason: "inappropriate_audio",
      details: "audio abuse",
    },
  );
  assert.equal(
    mafiaReportBody({
      targetPlayerId: 7,
      commandId: "report-12345678",
      reason: "invented",
    }),
    null,
  );
});

test("voice grants isolate mafia night and silence eliminated players", () => {
  const room = { id: 1, voice_room_name: "mafia-1", status: "night" };
  const mafia = mafiaVoicePermissions(room, { id: 1, team: "mafia", life_status: "alive" });
  const citizen = mafiaVoicePermissions(room, { id: 2, team: "town", life_status: "alive" });
  const dead = mafiaVoicePermissions(
    { ...room, status: "day_discussion" },
    { id: 3, team: "town", life_status: "dead" },
  );
  assert.equal(mafia.canPublish, true);
  assert.equal(mafia.canSubscribe, true);
  assert.equal(citizen.canPublish, false);
  assert.equal(citizen.canSubscribe, false);
  assert.equal(dead.canPublish, false);
  assert.equal(dead.canSubscribe, true);
  const deadAtNight = mafiaVoicePermissions(
    room,
    { id: 4, team: "town", life_status: "dead" },
  );
  assert.equal(deadAtNight.canPublish, false);
  assert.equal(deadAtNight.canSubscribe, true);
});

test("defense voice only opens nominated players", () => {
  const room = { id: 1, voice_room_name: "mafia-1", status: "day_defense" };
  assert.equal(
    mafiaVoicePermissions(room, { id: 5, team: "town", life_status: "alive" }, [5, 7]).canPublish,
    true,
  );
  assert.equal(
    mafiaVoicePermissions(room, { id: 6, team: "town", life_status: "alive" }, [5, 7]).canPublish,
    false,
  );
});
