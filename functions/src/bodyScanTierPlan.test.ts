/** @see ../../docs/body-scan-tier-composer.md — run `npm test` from `functions/` */
import assert from "node:assert/strict";
import { test } from "node:test";
import type { FractionalClip } from "./fractionalComposer";
import {
  collectBodyInstructions,
  distributeGapsBetweenBounds,
  distributeGapsEqual,
  minVariableSilenceBudget,
  pickEntryClip,
  pickIntroClips,
  chooseBodyScanPlan,
  stripEntryAnchorInstruction,
  variableGapSlotCount,
} from "./bodyScanTierPlan";

const macro = (zone: 1 | 2 | 3, id: string, ou: number, od: number): FractionalClip => ({
  clipId: id,
  role: "instruction",
  order: ou,
  text: id,
  voices: { Asaf: "gs://x" },
  macroZone: zone,
  bodyTier: "macro",
  orderUp: ou,
  orderDown: od,
});

const micro = (zone: 1 | 2 | 3, id: string, ou: number, od: number): FractionalClip => ({
  clipId: id,
  role: "instruction",
  order: ou,
  text: id,
  voices: { Asaf: "gs://x" },
  macroZone: zone,
  bodyTier: "micro",
  orderUp: ou,
  orderDown: od,
});

test("variableGapSlotCount treats outros like body parts", () => {
  assert.equal(variableGapSlotCount(3, 0), 3);
  assert.equal(variableGapSlotCount(3, 1), 4);
  assert.equal(variableGapSlotCount(3, 2), 5);
});

test("minVariableSilenceBudget tightens when outros are included", () => {
  assert.equal(minVariableSilenceBudget(3, 0), 30);
  assert.equal(minVariableSilenceBudget(3, 1), 60);
  assert.equal(minVariableSilenceBudget(3, 2), 75);
});

test("distributeGapsEqual splits evenly", () => {
  assert.deepEqual(distributeGapsEqual(10, 3), [4, 3, 3]);
  assert.deepEqual(distributeGapsEqual(9, 3), [3, 3, 3]);
  assert.deepEqual(distributeGapsEqual(0, 2), [0, 0]);
  assert.deepEqual(distributeGapsEqual(7, 1), [7]);
});

test("distributeGapsBetweenBounds sums to target within caps", () => {
  const { gaps, trailingFromGaps } = distributeGapsBetweenBounds(4, 80, 15, 25);
  assert.equal(trailingFromGaps, 0);
  assert.equal(gaps.length, 4);
  assert.equal(gaps.reduce((a, b) => a + b, 0), 80);
  for (const g of gaps) {
    assert.ok(g >= 15 && g <= 25);
  }
});

test("distributeGapsBetweenBounds spills to trailing when above max sum", () => {
  const { gaps, trailingFromGaps } = distributeGapsBetweenBounds(2, 100, 15, 25);
  assert.deepEqual(gaps, [25, 25]);
  assert.equal(trailingFromGaps, 50);
});

test("collectBodyInstructions up uses zones 1,2,3 macro order", () => {
  const clips: FractionalClip[] = [
    macro(1, "Z1", 1, 1),
    macro(2, "Z2", 2, 2),
    macro(3, "Z3", 3, 3),
  ];
  const got = collectBodyInstructions(clips, ["macro", "macro", "macro"], "up");
  assert.deepEqual(
    got.map((c) => c.clipId),
    ["Z1", "Z2", "Z3"]
  );
});

test("collectBodyInstructions down reverses zones", () => {
  const clips: FractionalClip[] = [
    macro(1, "Z1", 1, 1),
    macro(2, "Z2", 2, 2),
    macro(3, "Z3", 3, 3),
  ];
  const got = collectBodyInstructions(clips, ["macro", "macro", "macro"], "down");
  assert.deepEqual(
    got.map((c) => c.clipId),
    ["Z3", "Z2", "Z1"]
  );
});

test("pickIntroClips orders short then long when both", () => {
  const clips: FractionalClip[] = [
    {
      clipId: "LONG",
      role: "intro",
      order: 0,
      text: "",
      voices: {},
      introVariant: "long",
    },
    {
      clipId: "SHORT",
      role: "intro",
      order: 0,
      text: "",
      voices: {},
      introVariant: "short",
    },
  ];
  assert.deepEqual(
    pickIntroClips(clips, true, true).map((c) => c.clipId),
    ["SHORT", "LONG"]
  );
  assert.deepEqual(
    pickIntroClips(clips, true, false).map((c) => c.clipId),
    ["SHORT"]
  );
  assert.deepEqual(
    pickIntroClips(clips, false, true).map((c) => c.clipId),
    ["LONG"]
  );
});

test("stripEntryAnchorInstruction removes first instruction of first scanned zone", () => {
  const bodyFull: FractionalClip[] = [
    micro(1, "FIRST_MICRO", 300, 1),
    micro(1, "SECOND_SAME_ZONE", 310, 2),
    macro(2, "Z2", 200, 200),
  ];

  const stripped = stripEntryAnchorInstruction(
    bodyFull,
    ["micro", "macro", "macro"],
    "up"
  );
  assert.ok(stripped);
  assert.deepEqual(
    stripped!.map((c) => c.clipId),
    ["SECOND_SAME_ZONE", "Z2"]
  );
});

test("pickEntryClip resolves top macro", () => {
  const clips: FractionalClip[] = [
    {
      clipId: "E",
      role: "entry",
      order: 0,
      text: "",
      voices: {},
      entryScanEnd: "top",
      entryTier: "macro",
    },
  ];
  const e = pickEntryClip(clips, "up", "macro");
  assert.ok(e);
  assert.equal(e!.clipId, "E");
});

test("chooseBodyScanPlan omits framing intros under 5 min when not at timeline start", () => {
  const clips: FractionalClip[] = [
    {
      clipId: "INTRO_S",
      role: "intro",
      order: 0,
      text: "",
      voices: {},
      introVariant: "short",
    },
    macro(1, "M1", 1, 1),
    macro(2, "M2", 2, 2),
    macro(3, "M3", 3, 3),
    {
      clipId: "I1",
      role: "integration",
      order: 99,
      text: "",
      voices: {},
      integrationOrder: 1,
    },
    {
      clipId: "I2",
      role: "integration",
      order: 100,
      text: "",
      voices: {},
      integrationOrder: 2,
    },
  ];

  const plan = chooseBodyScanPlan(clips, {
    durationSec: 180,
    bodyScanDirection: "up",
    introShort: true,
    introLong: false,
    includeEntry: false,
    voiceId: "Asaf",
    moduleId: "BS_FRAC",
    atTimelineStart: false,
  });
  assert.equal(plan.intros.length, 0);
});

test("chooseBodyScanPlan keeps framing intros under 5 min when at timeline start", () => {
  const clips: FractionalClip[] = [
    {
      clipId: "INTRO_S",
      role: "intro",
      order: 0,
      text: "",
      voices: {},
      introVariant: "short",
    },
    macro(1, "M1", 1, 1),
    macro(2, "M2", 2, 2),
    macro(3, "M3", 3, 3),
    {
      clipId: "I1",
      role: "integration",
      order: 99,
      text: "",
      voices: {},
      integrationOrder: 1,
    },
    {
      clipId: "I2",
      role: "integration",
      order: 100,
      text: "",
      voices: {},
      integrationOrder: 2,
    },
  ];

  const plan = chooseBodyScanPlan(clips, {
    durationSec: 180,
    bodyScanDirection: "up",
    introShort: true,
    introLong: false,
    includeEntry: false,
    voiceId: "Asaf",
    moduleId: "BS_FRAC",
    atTimelineStart: true,
  });
  assert.equal(plan.intros.length, 1);
  assert.equal(plan.intros[0]!.clipId, "INTRO_S");
});

test("chooseBodyScanPlan skips first body when includeEntry", () => {
  const clips: FractionalClip[] = [
    {
      clipId: "INTRO_S",
      role: "intro",
      order: 0,
      text: "",
      voices: {},
      introVariant: "short",
    },
    {
      clipId: "ENT",
      role: "entry",
      order: 0,
      text: "",
      voices: {},
      entryScanEnd: "top",
      entryTier: "macro",
    },
    macro(1, "M1", 1, 1),
    macro(2, "M2", 2, 2),
    macro(3, "M3", 3, 3),
    {
      clipId: "I1",
      role: "integration",
      order: 99,
      text: "",
      voices: {},
      integrationOrder: 1,
    },
    {
      clipId: "I2",
      role: "integration",
      order: 100,
      text: "",
      voices: {},
      integrationOrder: 2,
    },
  ];

  const withEntry = chooseBodyScanPlan(clips, {
    durationSec: 1200,
    bodyScanDirection: "up",
    introShort: true,
    introLong: false,
    includeEntry: true,
    voiceId: "Asaf",
    moduleId: "BS_FRAC",
  });
  assert.ok(!withEntry.bodyInstructions.some((c) => c.clipId === "M1"));
  assert.ok(withEntry.bodyInstructions.some((c) => c.clipId === "M2"));

  const noEntry = chooseBodyScanPlan(clips, {
    durationSec: 1200,
    bodyScanDirection: "up",
    introShort: true,
    introLong: false,
    includeEntry: false,
    voiceId: "Asaf",
    moduleId: "BS_FRAC",
  });
  assert.ok(noEntry.bodyInstructions.some((c) => c.clipId === "M1"));
});
