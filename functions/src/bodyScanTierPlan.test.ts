import assert from "node:assert/strict";
import { test } from "node:test";
import type { FractionalClip } from "./fractionalComposer";
import {
  collectBodyInstructions,
  distributeGapsBetweenBounds,
  pickEntryClip,
  chooseBodyScanPlan,
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
    introStyle: "short",
    includeEntry: true,
    voiceId: "Asaf",
    moduleId: "BS_FRAC",
  });
  assert.ok(!withEntry.bodyInstructions.some((c) => c.clipId === "M1"));
  assert.ok(withEntry.bodyInstructions.some((c) => c.clipId === "M2"));

  const noEntry = chooseBodyScanPlan(clips, {
    durationSec: 1200,
    bodyScanDirection: "up",
    introStyle: "short",
    includeEntry: false,
    voiceId: "Asaf",
    moduleId: "BS_FRAC",
  });
  assert.ok(noEntry.bodyInstructions.some((c) => c.clipId === "M1"));
});
