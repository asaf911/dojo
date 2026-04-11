/**
 * NF_FRAC / IM_FRAC timeline: monotonic reminder silences, no overrun, IM pair gap.
 * @see ../../docs/fractional-module-composition.md
 */
import assert from "node:assert/strict";
import * as fs from "fs";
import * as path from "path";
import { test } from "node:test";
import { composeFractionalPlan, type FractionalClip } from "./fractionalComposer";
import { FRACTIONAL_FIRST_SPEECH_OFFSET_SEC } from "./fractionalSessionConstants";
import { clipDurationSec } from "./fractionalTimeline";

const catalogDir = path.join(__dirname, "..", "catalogs");

function loadCatalog(name: string): FractionalClip[] {
  const raw = fs.readFileSync(path.join(catalogDir, name), "utf8");
  const data = JSON.parse(raw) as { clips: FractionalClip[] };
  return data.clips;
}

function assertNoOverrun(
  plan: { items: { atSec: number; clipId: string }[]; durationSec: number },
  clips: FractionalClip[]
): void {
  const byId = new Map(clips.map((c) => [c.clipId, c]));
  for (const it of plan.items) {
    const c = byId.get(it.clipId);
    assert.ok(c, `clip ${it.clipId}`);
    assert.ok(
      it.atSec + clipDurationSec(c) <= plan.durationSec + 0.5,
      `overrun ${it.clipId} ends after duration`
    );
  }
}

/** Silence between end of reminder i-1 and start of reminder i (monotonic non-decreasing). */
function interReminderSilences(
  items: { atSec: number; clipId: string; role: string }[],
  clips: FractionalClip[]
): number[] {
  const byId = new Map(clips.map((c) => [c.clipId, c]));
  const rems = items
    .filter((i) => i.role === "reminder")
    .sort((a, b) => a.atSec - b.atSec);
  const silences: number[] = [];
  for (let i = 1; i < rems.length; i++) {
    const prev = byId.get(rems[i - 1].clipId)!;
    const endPrev = rems[i - 1].atSec + clipDurationSec(prev);
    silences.push(rems[i].atSec - endPrev);
  }
  return silences;
}

/** Integer atSec rounding can shift observed silence by ~1s vs float schedule; allow small slack. */
function assertMonotonicNonDecreasing(xs: number[], slackSec = 2): void {
  for (let i = 1; i < xs.length; i++) {
    assert.ok(
      xs[i] + slackSec >= xs[i - 1],
      `expected roughly monotonic silences, got ${JSON.stringify(xs)}`
    );
  }
}

const nfClips = loadCatalog("nostril_focus_fractional.json");
const imClips = loadCatalog("i_am_mantra_fractional.json");

for (const dur of [60, 120, 180, 240, 300]) {
  test(`NF_FRAC ${dur}s: no overrun, monotonic reminder silences`, () => {
    const plan = composeFractionalPlan(nfClips, dur, "Asaf", "NF_FRAC", true);
    assertNoOverrun(plan, nfClips);
    const silences = interReminderSilences(plan.items, nfClips);
    assertMonotonicNonDecreasing(silences);
  });

  test(`IM_FRAC ${dur}s: no overrun, monotonic reminder silences`, () => {
    const plan = composeFractionalPlan(imClips, dur, "Asaf", "IM_FRAC", true);
    assertNoOverrun(plan, imClips);
    const silences = interReminderSilences(plan.items, imClips);
    assertMonotonicNonDecreasing(silences);
  });
}

test("IM_FRAC IM_C002→IM_C003 gap is 5s when both scheduled", () => {
  const plan = composeFractionalPlan(imClips, 300, "Asaf", "IM_FRAC", true);
  const im2 = plan.items.find((i) => i.clipId === "IM_C002");
  const im3 = plan.items.find((i) => i.clipId === "IM_C003");
  if (!im2 || !im3) {
    return;
  }
  const c2 = imClips.find((c) => c.clipId === "IM_C002")!;
  const gap = im3.atSec - im2.atSec - clipDurationSec(c2);
  assert.ok(Math.abs(gap - 5) < 0.5, `expected ~5s gap, got ${gap}`);
});

test("IM_FRAC 120s caps reminders at 2", () => {
  const plan = composeFractionalPlan(imClips, 120, "Asaf", "IM_FRAC", true);
  const n = plan.items.filter((i) => i.role === "reminder").length;
  assert.ok(n <= 2, `expected at most 2 reminders for 120s IM, got ${n}`);
});

test("IM_FRAC 300s caps reminders at 4", () => {
  const plan = composeFractionalPlan(imClips, 300, "Asaf", "IM_FRAC", true);
  const n = plan.items.filter((i) => i.role === "reminder").length;
  assert.ok(n <= 4, `expected at most 4 reminders for 300s IM, got ${n}`);
});

test("composeFractionalPlan NF skips intro under 5m when not timeline start (catalog)", () => {
  const plan = composeFractionalPlan(nfClips, 180, "Asaf", "NF_FRAC", false);
  assert.ok(!plan.items.some((i) => i.role === "intro"));
});

test("composeFractionalPlan NF includes intro under 5m when at timeline start (catalog)", () => {
  const plan = composeFractionalPlan(nfClips, 180, "Asaf", "NF_FRAC", true);
  assert.ok(plan.items.some((i) => i.role === "intro"));
  assert.equal(plan.items[0]?.clipId, "NF_C001");
  assert.equal(plan.items[0]?.atSec, FRACTIONAL_FIRST_SPEECH_OFFSET_SEC);
});

test("composeFractionalPlan NF first cue at 0 when not at timeline start (catalog)", () => {
  const plan = composeFractionalPlan(nfClips, 180, "Asaf", "NF_FRAC", false);
  assert.ok(plan.items.length > 0);
  assert.equal(plan.items[0]?.atSec, 0);
});
