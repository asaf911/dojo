import assert from "node:assert/strict";
import { test } from "node:test";
import { shouldForceMeditationIntent } from "./aiRequestIntentRouting";

test("shouldForceMeditationIntent: valid blueprint id", () => {
  assert.equal(
    shouldForceMeditationIntent({
      blueprintId: "timely.morning",
      meditationThemes: undefined,
      prompt: "anything",
      historyLen: 0,
    }),
    true
  );
});

test("shouldForceMeditationIntent: invalid blueprint id falls through to prompt rules", () => {
  assert.equal(
    shouldForceMeditationIntent({
      blueprintId: "not.a.real.blueprint",
      meditationThemes: ["morning"],
      prompt: "Create a 10-minute morning meditation.",
      historyLen: 0,
    }),
    true
  );
});

test("shouldForceMeditationIntent: themes + Create a … meditation + empty history", () => {
  assert.equal(
    shouldForceMeditationIntent({
      blueprintId: null,
      meditationThemes: ["evening"],
      prompt: "Create a 10-minute evening wind-down meditation.",
      historyLen: 0,
    }),
    true
  );
});

test("shouldForceMeditationIntent: no themes and no blueprint", () => {
  assert.equal(
    shouldForceMeditationIntent({
      blueprintId: null,
      meditationThemes: [],
      prompt: "Create a 10-minute morning meditation.",
      historyLen: 0,
    }),
    false
  );
});

test("shouldForceMeditationIntent: with chat history do not force on themes alone", () => {
  assert.equal(
    shouldForceMeditationIntent({
      blueprintId: null,
      meditationThemes: ["morning"],
      prompt: "Create a 10-minute morning meditation.",
      historyLen: 1,
    }),
    false
  );
});
