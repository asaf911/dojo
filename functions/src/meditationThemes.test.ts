import assert from "node:assert/strict";
import { test } from "node:test";
import {
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
