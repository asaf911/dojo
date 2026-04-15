import assert from "node:assert/strict";
import { test } from "node:test";
import {
  pickDisplayTitle,
  resolveDisplayTitleBucket,
  type DisplayTitleBucket,
} from "./aiMeditationDisplayTitle";
import type { MeditationThemeId } from "./meditationThemes";
import type { SessionPreferences, UserStructureOverrides } from "./phaseAllocation";

const prefsBase: SessionPreferences = {
  noBreathwork: false,
  isSleep: false,
  isMorning: false,
  isEvening: false,
};

const overridesEmpty: UserStructureOverrides = {};

function bucketFor(
  prompt: string,
  themes: MeditationThemeId[],
  prefs: SessionPreferences,
  mvVariant: "MV_KM" | "MV_GR" | null,
  evVariant: "EV_KM" | "EV_GR" | null,
  overrides: UserStructureOverrides,
  structureContext: string
): DisplayTitleBucket {
  return resolveDisplayTitleBucket({
    prompt,
    themes,
    prefs,
    mvVariant,
    evVariant,
    overrides,
    structureContext,
  });
}

test("resolveDisplayTitleBucket: sleep prompt", () => {
  assert.equal(
    bucketFor(
      "help me sleep",
      [],
      { ...prefsBase, isSleep: true },
      null,
      null,
      overridesEmpty,
      "PB_FRAC@s1"
    ),
    "sleep"
  );
});

test("resolveDisplayTitleBucket: MV_KM wins over morning theme", () => {
  assert.equal(
    bucketFor(
      "4m morning visualization",
      ["morning"],
      prefsBase,
      "MV_KM",
      null,
      overridesEmpty,
      "MV_KM_FRAC@s2"
    ),
    "morning_viz_km"
  );
});

test("resolveDisplayTitleBucket: MV_GR", () => {
  assert.equal(
    bucketFor(
      "gratitude visualization",
      ["gratitude", "morning"],
      prefsBase,
      "MV_GR",
      null,
      overridesEmpty,
      "MV_GR_FRAC@s2"
    ),
    "morning_viz_gr"
  );
});

test("resolveDisplayTitleBucket: EV_KM wins over evening theme", () => {
  assert.equal(
    bucketFor(
      "evening visualization unwind",
      ["evening"],
      prefsBase,
      null,
      "EV_KM",
      overridesEmpty,
      "EV_KM_FRAC@s2"
    ),
    "evening_viz_km"
  );
});

test("resolveDisplayTitleBucket: EV_GR", () => {
  assert.equal(
    bucketFor(
      "evening gratitude visualization",
      ["evening", "gratitude"],
      prefsBase,
      null,
      "EV_GR",
      overridesEmpty,
      "EV_GR_FRAC@s2"
    ),
    "evening_viz_gr"
  );
});

test("resolveDisplayTitleBucket: NF override", () => {
  assert.equal(
    bucketFor(
      "5m nostril focus",
      [],
      prefsBase,
      null,
      null,
      { focusType: "NF" },
      "NF_FRAC@s3"
    ),
    "focus"
  );
});

test("resolveDisplayTitleBucket: IM_FRAC in structure", () => {
  assert.equal(
    bucketFor("custom", [], prefsBase, null, null, overridesEmpty, "IM_FRAC@s2"),
    "focus"
  );
});

test("resolveDisplayTitleBucket: anxiety keywords", () => {
  assert.equal(
    bucketFor("calm my racing thoughts", [], prefsBase, null, null, overridesEmpty, "PB_FRAC@s1"),
    "anxiety"
  );
});

test("resolveDisplayTitleBucket: relax keywords", () => {
  assert.equal(
    bucketFor("10m relaxation", [], prefsBase, null, null, overridesEmpty, "PB_FRAC@s1"),
    "relax"
  );
});

test("resolveDisplayTitleBucket: morning_general when morning theme, no mv", () => {
  assert.equal(
    bucketFor("good morning 5m", ["morning"], prefsBase, null, null, overridesEmpty, "PB_FRAC@s1"),
    "morning_general"
  );
});

test("pickDisplayTitle: same hash + same randomIndex → same title", () => {
  const args = {
    prompt: "4m morning visualization",
    duration: 4,
    themes: ["morning"] satisfies MeditationThemeId[],
    prefs: prefsBase,
    mvVariant: "MV_KM" as const,
    evVariant: null,
    overrides: overridesEmpty,
    structureContext: "PB_FRAC@s1,MV_KM_FRAC@s2",
  };
  const a = pickDisplayTitle(args, { randomIndex: () => 3 });
  const b = pickDisplayTitle(args, { randomIndex: () => 3 });
  assert.equal(a.bucket, "morning_viz_km");
  assert.equal(a.title, b.title);
});

test("pickDisplayTitle: different randomIndex can change title", () => {
  const args = {
    prompt: "4m morning visualization",
    duration: 4,
    themes: ["morning"] satisfies MeditationThemeId[],
    prefs: prefsBase,
    mvVariant: "MV_KM" as const,
    evVariant: null,
    overrides: overridesEmpty,
    structureContext: "PB_FRAC@s1,MV_KM_FRAC@s2",
  };
  const titles = new Set<string>();
  for (let i = 0; i < 40; i++) {
    titles.add(
      pickDisplayTitle(args, { randomIndex: (max) => i % max }).title
    );
  }
  assert.ok(titles.size >= 2, "expected some title variety across random indices");
});
