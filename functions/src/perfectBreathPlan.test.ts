/** @see ../../docs/perfect-breath-fractional-composer.md */
import assert from "node:assert/strict";
import { test } from "node:test";
import type { FractionalClip } from "./fractionalComposer";
import { composePerfectBreathPlan } from "./perfectBreathPlan";

const D = 3;

function c(
  clipId: string,
  role: FractionalClip["role"] = "instruction",
  extra: Partial<FractionalClip> = {}
): FractionalClip {
  return {
    clipId,
    role,
    order: 0,
    text: clipId,
    voices: { Asaf: `gs://b/${clipId}.mp3` },
    durationSec: D,
    ...extra,
  };
}

const ALL_IDS = [
  "PBV_OPEN_000_INTRO_ASAF",
  "PBV_BREATH_100",
  "PBV_BREATH_110",
  "PBV_BREATH_120",
  "PBV_BREATH_130",
  "PBV_BREATH_140",
  "PBV_BREATH_150",
  "PBV_BREATH_160",
  "PBV_BREATH_170",
  "PBV_BREATH_200_INHALE_DEEP_AND_HOLD_TOP_ASAF",
  "PBV_BREATH_230_SQUEEZE_AIR_TOP_OF_BELLY_LOWER_LUNGS_ASAF",
  "PBV_BREATH_240_RELEASE_HOLD_10S_ASAF",
  "PBV_BREATH_242_RELEASE_HOLD_15S_ASAF",
  "PBV_BREATH_244_RELEASE_HOLD_20S_ASAF",
  "PBV_BREATH_246_RELEASE_HOLD_25S_ASAF",
  "PBV_BREATH_248_RELEASE_HOLD_30S_ASAF",
  "PBV_HOLD_250_THOUGHTS_ESCAPE_ASAF",
  "PBV_BREATH_280_INHALE_RECOVERY_ASAF",
  "PBV_BREATH_320_FINAL_EXHALE_ASAF",
  "PBV_BREATH_322_FINAL_EXHALE_NEXT_CYCLE_ASAF",
  "PBS_IN",
  "PBS_OUT",
];

function mockCatalog(): FractionalClip[] {
  return ALL_IDS.map((id) =>
    c(id, id.includes("OPEN") ? "intro" : id.includes("320") || id.includes("322") ? "outro" : "instruction")
  );
}

test("composePerfectBreathPlan ends with 320 on last cycle only", () => {
  const plan = composePerfectBreathPlan(mockCatalog(), 600, "Asaf", "PB_FRAC");
  const last = plan.items[plan.items.length - 1];
  assert.equal(last.clipId, "PBV_BREATH_320_FINAL_EXHALE_ASAF");
  assert.ok(last.parallel?.clipId === "PBS_OUT");
});

test("composePerfectBreathPlan adds parallel PBS_IN on preparation inhale", () => {
  const plan = composePerfectBreathPlan(mockCatalog(), 600, "Asaf", "PB_FRAC");
  const inh = plan.items.find((i) => i.clipId === "PBV_BREATH_100");
  assert.ok(inh);
  assert.equal(inh!.parallel?.clipId, "PBS_IN");
});

test("composePerfectBreathPlan single long session may include 322 before final 320", () => {
  const plan = composePerfectBreathPlan(mockCatalog(), 1200, "Asaf", "PB_FRAC");
  const has322 = plan.items.some((i) => i.clipId === "PBV_BREATH_322_FINAL_EXHALE_NEXT_CYCLE_ASAF");
  const last = plan.items[plan.items.length - 1];
  assert.equal(last.clipId, "PBV_BREATH_320_FINAL_EXHALE_ASAF");
  if (plan.items.filter((i) => i.clipId === "PBV_BREATH_322_FINAL_EXHALE_NEXT_CYCLE_ASAF").length > 0) {
    assert.ok(has322);
  }
});

/** Integer second when a cue may fire; must match `voiceTriggerSec` in perfectBreathPlan.ts */
function voiceTriggerSec(cursor: number): number {
  const eps = 1e-9;
  return Math.max(0, Math.ceil(cursor - eps));
}

test("composePerfectBreathPlan preparation inhale never overlaps next exhale (fractional durations)", () => {
  const clips = mockCatalog().map((x) => {
    if (x.clipId === "PBV_BREATH_100") return { ...x, durationSec: 7.967 };
    if (x.clipId === "PBV_BREATH_110") return { ...x, durationSec: 4.989 };
    if (x.clipId === "PBV_BREATH_120") return { ...x, durationSec: 5.799 };
    if (x.clipId === "PBV_BREATH_130") return { ...x, durationSec: 2.064 };
    return x;
  });
  const plan = composePerfectBreathPlan(clips, 600, "Asaf", "PB_FRAC");
  const byId = new Map(clips.map((c) => [c.clipId, c.durationSec]));
  const prepPairs: [string, string][] = [
    ["PBV_BREATH_100", "PBV_BREATH_110"],
    ["PBV_BREATH_120", "PBV_BREATH_130"],
    ["PBV_BREATH_140", "PBV_BREATH_150"],
    ["PBV_BREATH_160", "PBV_BREATH_170"],
  ];
  for (const [inhId, exhId] of prepPairs) {
    const inh = plan.items.find((i) => i.clipId === inhId);
    const exh = plan.items.find((i) => i.clipId === exhId);
    assert.ok(inh && exh, `missing ${inhId} or ${exhId}`);
    const dInh = byId.get(inhId);
    assert.ok(typeof dInh === "number");
    const earliestExh = voiceTriggerSec(inh!.atSec + dInh!);
    assert.ok(
      exh!.atSec >= earliestExh,
      `overlap: ${inhId}@${inh!.atSec}s + ${dInh}s ends after ${earliestExh - 1}s, but ${exhId}@${exh!.atSec}s`
    );
  }
});
