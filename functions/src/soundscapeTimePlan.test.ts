import assert from "node:assert/strict";
import { test } from "node:test";
import { getBlueprintById } from "./meditationBlueprints";
import { SOUNDSCAPE_TIME_PLAN } from "./soundscapeTimePlan";

test("SOUNDSCAPE_TIME_PLAN morning prefers OA, BD, PT", () => {
  assert.deepEqual(SOUNDSCAPE_TIME_PLAN["timely.morning"].preferredIds, [
    "OA",
    "BD",
    "PT",
  ]);
  assert.equal(SOUNDSCAPE_TIME_PLAN["timely.morning"].avoidIds, undefined);
});

test("SOUNDSCAPE_TIME_PLAN noon prefers DH, SP, LI", () => {
  assert.deepEqual(SOUNDSCAPE_TIME_PLAN["timely.noon"].preferredIds, [
    "DH",
    "SP",
    "LI",
  ]);
});

test("SOUNDSCAPE_TIME_PLAN evening and night prefer OC, ES, LI and avoid OA", () => {
  for (const id of ["timely.evening", "timely.night"] as const) {
    assert.deepEqual(SOUNDSCAPE_TIME_PLAN[id].preferredIds, ["OC", "ES", "LI"]);
    assert.deepEqual(SOUNDSCAPE_TIME_PLAN[id].avoidIds, ["OA"]);
  }
});

test("blueprints merge soundscape plan for timely morning/noon/evening/night", () => {
  const morning = getBlueprintById("timely.morning");
  assert.deepEqual(morning.audioHints.backgroundSound?.preferredIds, [
    "OA",
    "BD",
    "PT",
  ]);
  assert.equal(morning.audioHints.backgroundSound?.preferCategory, undefined);

  const noon = getBlueprintById("timely.noon");
  assert.deepEqual(noon.audioHints.backgroundSound?.preferredIds, [
    "DH",
    "SP",
    "LI",
  ]);

  const evening = getBlueprintById("timely.evening");
  assert.deepEqual(evening.audioHints.backgroundSound?.preferredIds, [
    "OC",
    "ES",
    "LI",
  ]);
  assert.deepEqual(evening.audioHints.backgroundSound?.avoidIds, ["OA"]);

  const night = getBlueprintById("timely.night");
  assert.deepEqual(night.audioHints.backgroundSound?.avoidIds, ["OA"]);
});

test("sleep and scenario blueprints keep preferCategory on background sound", () => {
  const sleep = getBlueprintById("timely.sleep");
  assert.equal(sleep.audioHints.backgroundSound?.preferCategory, "sleep");
  const scenario = getBlueprintById("scenario.pre_important_event");
  assert.equal(scenario.audioHints.backgroundSound?.preferCategory, "focus");
});
