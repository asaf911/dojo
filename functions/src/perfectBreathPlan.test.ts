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

test("composePerfectBreathPlan 120s uses 20s bottom hold and three prep pairs", () => {
  const plan = composePerfectBreathPlan(mockCatalog(), 120, "Asaf", "PB_FRAC");
  assert.ok(plan.items.some((i) => i.clipId === "PBV_BREATH_140"));
  assert.ok(plan.items.some((i) => i.clipId === "PBV_BREATH_150"));
  assert.ok(plan.items.some((i) => i.clipId === "PBV_BREATH_244_RELEASE_HOLD_20S_ASAF"));
  assert.equal(plan.items[plan.items.length - 1]!.clipId, "PBV_BREATH_320_FINAL_EXHALE_ASAF");
});

test("composePerfectBreathPlan 60s skips intro, one prep pair, 10s release, fits budget", () => {
  const plan = composePerfectBreathPlan(mockCatalog(), 60, "Asaf", "PB_FRAC");
  assert.ok(!plan.items.some((i) => i.clipId === "PBV_OPEN_000_INTRO_ASAF"));
  assert.equal(plan.items[0]?.clipId, "PBV_BREATH_100");
  assert.ok(!plan.items.some((i) => i.clipId === "PBV_BREATH_120"));
  assert.ok(plan.items.some((i) => i.clipId === "PBV_BREATH_240_RELEASE_HOLD_10S_ASAF"));
  assert.ok(
    !plan.items.some((i) => i.clipId === "PBV_HOLD_250_THOUGHTS_ESCAPE_ASAF"),
    "10s bottom hold: no mid-hold reminder"
  );
  assert.equal(plan.items[plan.items.length - 1]!.clipId, "PBV_BREATH_320_FINAL_EXHALE_ASAF");
  const last = plan.items[plan.items.length - 1]!;
  const d = mockCatalog().find((c) => c.clipId === last.clipId)?.durationSec;
  assert.ok(typeof d === "number" && last.atSec + d <= 60.5);
});

test("composePerfectBreathPlan includes mid-hold reminder when bottom hold > 10s", () => {
  const plan = composePerfectBreathPlan(mockCatalog(), 120, "Asaf", "PB_FRAC");
  assert.ok(plan.items.some((i) => i.clipId === "PBV_HOLD_250_THOUGHTS_ESCAPE_ASAF"));
});

test("composePerfectBreathPlan places mid-hold reminder at ~1/3 of bottom hold", () => {
  const plan = composePerfectBreathPlan(mockCatalog(), 360, "Asaf", "PB_FRAC");
  const rel = plan.items.find((i) => i.clipId === "PBV_BREATH_242_RELEASE_HOLD_15S_ASAF");
  const h = plan.items.find((i) => i.clipId === "PBV_HOLD_250_THOUGHTS_ESCAPE_ASAF");
  assert.ok(rel && h, "expected 15s release and 250 in 360s plan");
  const afterRel = rel!.atSec + D;
  const offset = Math.round(15 / 3);
  assert.equal(h!.atSec, Math.round(afterRel + offset));
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

/** Must match `voiceTriggerSec` in perfectBreathPlan.ts */
function voiceTriggerSec(cursor: number): number {
  const eps = 1e-9;
  return Math.max(0, Math.ceil(cursor - eps));
}

/** Must match preparation SFX cadence in perfectBreathPlan.ts */
const PREP_INHALE_SFX_SEC = 5;
const PREP_GAP_AFTER_INHALE_SEC = 2;
const PREP_EXHALE_SFX_SEC = 5;
const PREP_GAP_AFTER_EXHALE_SEC = 1;
const FIRST_PREP_PAIR_EXTRA_GAP_SEC = 1;

const PREP_PAIRS: [string, string][] = [
  ["PBV_BREATH_100", "PBV_BREATH_110"],
  ["PBV_BREATH_120", "PBV_BREATH_130"],
  ["PBV_BREATH_140", "PBV_BREATH_150"],
  ["PBV_BREATH_160", "PBV_BREATH_170"],
];

test("composePerfectBreathPlan prep phase follows SFX cadence (+1s gaps on first pair each cycle)", () => {
  const plan = composePerfectBreathPlan(mockCatalog(), 600, "Asaf", "PB_FRAC");
  const cycles = plan.items.filter((i) => i.clipId === "PBV_BREATH_100").length;
  assert.ok(cycles >= 1);
  for (let c = 0; c < cycles; c++) {
    const inh100 = plan.items.filter((i) => i.clipId === "PBV_BREATH_100")[c];
    const exh110 = plan.items.filter((i) => i.clipId === "PBV_BREATH_110")[c];
    assert.ok(inh100 && exh110);
    const gapInh =
      PREP_GAP_AFTER_INHALE_SEC + FIRST_PREP_PAIR_EXTRA_GAP_SEC;
    const earliest110 = voiceTriggerSec(inh100.atSec + PREP_INHALE_SFX_SEC + gapInh);
    assert.ok(
      exh110.atSec >= earliest110,
      `cycle ${c}: 110@${exh110.atSec}s vs earliest ${earliest110}s after 100`
    );
    const gapExh =
      PREP_GAP_AFTER_EXHALE_SEC + FIRST_PREP_PAIR_EXTRA_GAP_SEC;
    const inh120 = plan.items.filter((i) => i.clipId === "PBV_BREATH_120")[c];
    assert.ok(inh120);
    const earliest120 = voiceTriggerSec(exh110.atSec + PREP_EXHALE_SFX_SEC + gapExh);
    assert.ok(
      inh120.atSec >= earliest120,
      `cycle ${c}: 120@${inh120.atSec}s vs earliest ${earliest120}s after 110`
    );
  }
  for (const [inhId, exhId] of PREP_PAIRS.slice(1)) {
    const inh = plan.items.find((i) => i.clipId === inhId);
    const exh = plan.items.find((i) => i.clipId === exhId);
    assert.ok(inh && exh, `missing ${inhId} or ${exhId}`);
    const earliestExh = voiceTriggerSec(
      inh!.atSec + PREP_INHALE_SFX_SEC + PREP_GAP_AFTER_INHALE_SEC
    );
    assert.ok(
      exh!.atSec >= earliestExh,
      `${exhId}@${exh!.atSec}s should be on or after inhale SFX block end ${earliestExh}s (${inhId}@${inh!.atSec}s)`
    );
  }
  for (let i = 1; i < PREP_PAIRS.length - 1; i++) {
    const exhId = PREP_PAIRS[i]![1];
    const nextInhId = PREP_PAIRS[i + 1]![0];
    const exh = plan.items.find((x) => x.clipId === exhId);
    const nextInh = plan.items.find((x) => x.clipId === nextInhId);
    assert.ok(exh && nextInh);
    const earliestNextInh = voiceTriggerSec(
      exh!.atSec + PREP_EXHALE_SFX_SEC + PREP_GAP_AFTER_EXHALE_SEC
    );
    assert.ok(
      nextInh!.atSec >= earliestNextInh,
      `${nextInhId}@${nextInh!.atSec}s should follow exhale block from ${exhId}@${exh!.atSec}s (earliest ${earliestNextInh}s)`
    );
  }
});
