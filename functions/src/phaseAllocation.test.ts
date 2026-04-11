import assert from "node:assert/strict";
import { test } from "node:test";
import {
  allocatePhases,
  minFocusMinutesForMorningVisualization,
  rebalanceAllocationForMinimumFocus,
} from "./phaseAllocation";

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
