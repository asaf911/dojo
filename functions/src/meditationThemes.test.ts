import assert from "node:assert/strict";
import { test } from "node:test";
import {
  resolveMorningVisualizationVariant,
  resolveMeditationThemes,
  themeCompositionHints,
  themesFromExploreTimeOfDay,
} from "./meditationThemes";
import type { UserStructureOverrides } from "./phaseAllocation";

test("themesFromExploreTimeOfDay maps midday → noon, night → sleep", () => {
  assert.deepEqual(themesFromExploreTimeOfDay("midday"), ["noon"]);
  assert.deepEqual(themesFromExploreTimeOfDay("night"), ["sleep"]);
  assert.deepEqual(themesFromExploreTimeOfDay("morning"), ["morning"]);
});

test("resolveMeditationThemes: Morning Gratitude — gratitude + morning, stable order", () => {
  const prefs = {
    noBreathwork: false,
    isSleep: false,
    isMorning: false,
    isEvening: false,
  };
  const themes = resolveMeditationThemes({
    prompt: "Morning gratitude practice",
    prefs,
  });
  assert.ok(themes.includes("gratitude"));
  assert.ok(themes.includes("morning"));
  assert.ok(themes.indexOf("gratitude") < themes.indexOf("morning"));
});

test("themeCompositionHints: Morning Gratitude — MV_GR focus, morning greeting", () => {
  const prefs = {
    noBreathwork: false,
    isSleep: false,
    isMorning: false,
    isEvening: false,
  };
  const overrides: UserStructureOverrides = {};
  const { fractionalContext, cueHints } = themeCompositionHints(
    ["gratitude", "morning"],
    prefs,
    overrides,
    5
  );
  assert.equal(cueHints.focusFractionalId, "MV_GR_FRAC");
  assert.equal(fractionalContext.greetingFamilyHint, "morning");
});

test("themeCompositionHints: user focusType NF wins over gratitude MV", () => {
  const prefs = {
    noBreathwork: false,
    isSleep: false,
    isMorning: false,
    isEvening: false,
  };
  const overrides: UserStructureOverrides = { focusType: "NF" };
  const { cueHints } = themeCompositionHints(
    ["gratitude", "morning"],
    prefs,
    overrides,
    5
  );
  assert.equal(cueHints.focusFractionalId, undefined);
});

test("resolveMorningVisualizationVariant: morning + visualization → MV_KM", () => {
  assert.equal(
    resolveMorningVisualizationVariant({
      prompt: "4minutes moning visualization",
      llmWants: null,
      mergedThemes: [],
    }),
    "MV_KM"
  );
});

test("resolveMorningVisualizationVariant: gratitude + visualization → MV_GR", () => {
  assert.equal(
    resolveMorningVisualizationVariant({
      prompt: "short gratitude visualization",
      llmWants: null,
      mergedThemes: [],
    }),
    "MV_GR"
  );
});

test("resolveMorningVisualizationVariant: LLM key_moments without viz word", () => {
  assert.equal(
    resolveMorningVisualizationVariant({
      prompt: "4m session",
      llmWants: "key_moments",
      mergedThemes: [],
    }),
    "MV_KM"
  );
});

test("themeCompositionHints: forced MV_KM when themes omit morning", () => {
  const prefs = {
    noBreathwork: false,
    isSleep: false,
    isMorning: false,
    isEvening: false,
  };
  const { cueHints } = themeCompositionHints(
    ["noon"],
    prefs,
    {},
    2,
    { forcedFocusFractionalId: "MV_KM_FRAC" }
  );
  assert.equal(cueHints.focusFractionalId, "MV_KM_FRAC");
});

test("themeCompositionHints: sleep suppresses morning greeting hint", () => {
  const prefs = {
    noBreathwork: false,
    isSleep: true,
    isMorning: false,
    isEvening: false,
  };
  const { fractionalContext } = themeCompositionHints(
    ["morning", "sleep"],
    prefs,
    {},
    3
  );
  assert.equal(fractionalContext.greetingFamilyHint, undefined);
});

test("resolveMeditationThemes: morning in prompt strips ambient sleep from client + explore night", () => {
  const prefs = {
    noBreathwork: false,
    isSleep: false,
    isMorning: false,
    isEvening: false,
  };
  const themes = resolveMeditationThemes({
    prompt: "Make a 5m morning gratitude",
    prefs,
    clientThemes: ["sleep"],
    exploreTimeOfDay: "night",
  });
  assert.ok(!themes.includes("sleep"), themes.join(","));
  assert.ok(themes.includes("morning"));
  assert.ok(themes.includes("gratitude"));
});

test("resolveMeditationThemes + themeCompositionHints: night context still yields MV_GR for morning gratitude", () => {
  const prefs = {
    noBreathwork: false,
    isSleep: false,
    isMorning: false,
    isEvening: false,
  };
  const themes = resolveMeditationThemes({
    prompt: "Make a 5m morning gratitude",
    prefs,
    clientThemes: ["sleep"],
    exploreTimeOfDay: "night",
  });
  const { fractionalContext, cueHints } = themeCompositionHints(
    themes,
    prefs,
    {},
    5
  );
  assert.equal(cueHints.focusFractionalId, "MV_GR_FRAC");
  assert.equal(fractionalContext.greetingFamilyHint, "morning");
});

test("resolveMeditationThemes: morning + explicit sleep in prompt keeps sleep", () => {
  const prefs = {
    noBreathwork: false,
    isSleep: false,
    isMorning: false,
    isEvening: false,
  };
  const themes = resolveMeditationThemes({
    prompt: "Morning meditation to help me sleep tonight",
    prefs,
    clientThemes: ["sleep"],
    exploreTimeOfDay: "night",
  });
  assert.ok(themes.includes("sleep"));
});
