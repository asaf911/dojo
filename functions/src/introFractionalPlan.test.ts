/** @see ../../docs/intro-fractional-composer.md */

import assert from "node:assert/strict";
import test from "node:test";
import type { FractionalClip } from "./fractionalComposer";
import {
  composeIntroFractionalPlanWithRng,
  INTRO_FRAC_END_PAUSE_SEC,
  INTRO_FRAC_FIRST_SPEECH_OFFSET_SEC,
} from "./introFractionalPlan";
import { clipDurationSec } from "./fractionalTimeline";

function clip(
  id: string,
  layer: "greeting" | "arrival" | "orientation",
  dur: number,
  order: number
): FractionalClip {
  return {
    clipId: id,
    role: "instruction",
    order,
    layer,
    text: id,
    voices: { Asaf: `gs://b/${id}.mp3` },
    durationSec: dur,
  };
}

const fullCatalog: FractionalClip[] = [
  clip("INT_GRT_100", "greeting", 2, 100),
  clip("INT_GRT_104", "greeting", 2, 104),
  clip("INT_GRT_106", "greeting", 2, 106),
  clip("INT_GRT_108", "greeting", 2, 108),
  clip("INT_ARR_120", "arrival", 4, 120),
  clip("INT_ARR_122", "arrival", 4, 122),
  clip("INT_ARR_124", "arrival", 3, 124),
  clip("INT_ARR_126", "arrival", 3, 126),
  clip("INT_ARR_128", "arrival", 2, 128),
  clip("INT_ARR_130", "arrival", 3, 130),
  clip("INT_ARR_132", "arrival", 3, 132),
  clip("INT_ORI_140", "orientation", 5, 140),
];

test("INT_FRAC: first cue at 7s", () => {
  const plan = composeIntroFractionalPlanWithRng(
    fullCatalog,
    120,
    "Asaf",
    "INT_FRAC",
    () => 0.42
  );
  assert.ok(plan.items.length >= 1);
  assert.equal(plan.items[0]!.atSec, INTRO_FRAC_FIRST_SPEECH_OFFSET_SEC);
});

test("INT_FRAC: timeline respects end pause", () => {
  const plan = composeIntroFractionalPlanWithRng(
    fullCatalog,
    120,
    "Asaf",
    "INT_FRAC",
    () => 0.42
  );
  let t = 0;
  for (let i = 0; i < plan.items.length; i++) {
    const it = plan.items[i]!;
    const c = fullCatalog.find((x) => x.clipId === it.clipId)!;
    t = it.atSec + clipDurationSec(c);
  }
  assert.ok(t + INTRO_FRAC_END_PAUSE_SEC <= 120 + 0.01);
});

test("INT_FRAC: at most one greeting clip", () => {
  const plan = composeIntroFractionalPlanWithRng(
    fullCatalog,
    120,
    "Asaf",
    "INT_FRAC",
    () => 0.77
  );
  const g = plan.items.filter((i) => i.clipId.startsWith("INT_GRT_"));
  assert.ok(g.length <= 1);
});

test("INT_FRAC: never both spine and free posture", () => {
  for (let s = 0; s < 20; s++) {
    const plan = composeIntroFractionalPlanWithRng(
      fullCatalog,
      120,
      "Asaf",
      "INT_FRAC",
      () => (Math.sin(s + 1) * 0.5 + 0.5) % 1
    );
    const ids = plan.items.map((i) => i.clipId);
    assert.ok(!(ids.includes("INT_ARR_120") && ids.includes("INT_ARR_122")));
    assert.ok(!(ids.includes("INT_ARR_124") && ids.includes("INT_ARR_126")));
  }
});

test("INT_FRAC: short window still returns at least one clip when possible", () => {
  const plan = composeIntroFractionalPlanWithRng(
    [clip("INT_ORI_140", "orientation", 3, 140)],
    17,
    "Asaf",
    "INT_FRAC",
    () => 0.5
  );
  assert.equal(plan.items.length, 1);
  assert.equal(plan.items[0]!.clipId, "INT_ORI_140");
});
