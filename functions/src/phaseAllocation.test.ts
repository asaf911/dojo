import assert from "node:assert/strict";
import { test } from "node:test";
import {
  allocatePhases,
  allocatePhasesFromOverrides,
  extractSessionPreferences,
  minFocusMinutesForMorningVisualization,
  promptIndicatesSleepPracticeIntent,
  rebalanceAllocationForMinimumFocus,
} from "./phaseAllocation";

test("promptIndicatesSleepPracticeIntent: negated sleep copy (morning blueprint) → false", () => {
  const p =
    "never sleep hypnosis. Do not use sleep, goodnight, or drift to sleep cues. Morning visualization.";
  assert.equal(promptIndicatesSleepPracticeIntent(p.toLowerCase()), false);
});

test("promptIndicatesSleepPracticeIntent: explicit sleep meditation → true", () => {
  assert.equal(
    promptIndicatesSleepPracticeIntent(
      "Create a 10-minute sleep meditation to quiet my mind".toLowerCase()
    ),
    true
  );
});

test("extractSessionPreferences: morning blueprint with sleep words → isSleep false", () => {
  const prefs = extractSessionPreferences(
    "Morning meditation. Never sleep hypnosis. Do not use sleep in the title."
  );
  assert.equal(prefs.isSleep, false);
  assert.equal(prefs.isMorning, true);
});

test("minFocusMinutesForMorningVisualization: 4m default → 2", () => {
  assert.equal(
    minFocusMinutesForMorningVisualization(4, "4 minutes morning visualization"),
    2
  );
});

test("minFocusMinutesForMorningVisualization: ultra short 4m → 1", () => {
  assert.equal(
    minFocusMinutesForMorningVisualization(
      4,
      "ultra short 4m morning visualization"
    ),
    1
  );
});

test("rebalanceAllocationForMinimumFocus: 4m table gains focus from relax", () => {
  const prefs = {
    noBreathwork: false,
    isSleep: false,
    isMorning: false,
    isEvening: false,
  };
  const base = allocatePhases(4, prefs);
  assert.equal(base.focus, 0);
  const out = rebalanceAllocationForMinimumFocus(base, 4, 2);
  assert.equal(out.breath + out.relax + out.focus + out.insight, 4);
  assert.equal(out.focus, 2);
  assert.equal(out.relax, 0);
  assert.equal(out.breath, 2);
});

test("allocatePhasesFromOverrides: mantraMinutes 0 without IM still yields default focus minutes", () => {
  const prefs = {
    noBreathwork: false,
    isSleep: false,
    isMorning: false,
    isEvening: false,
  };
  const out = allocatePhasesFromOverrides(
    5,
    { totalDuration: 5, mantraMinutes: 0 },
    prefs
  );
  assert.ok(out.focus > 0, `focus=${out.focus}`);
  assert.equal(out.breath + out.relax + out.focus + out.insight, 5);
});
