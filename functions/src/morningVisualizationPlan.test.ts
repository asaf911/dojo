/**
 * Morning Visualization: theme filter, ordering, reminder gating, no overrun.
 */
import assert from "node:assert/strict";
import * as fs from "fs";
import * as path from "path";
import { test } from "node:test";
import type { FractionalClip } from "./fractionalComposer";
import { composeMorningVisualizationPlan } from "./morningVisualizationPlan";
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

const mvClips = loadCatalog("morning_visualization_fractional.json");

test("MV_KM_FRAC 300s atTimelineStart: intros then instructions before outros", () => {
  const plan = composeMorningVisualizationPlan(
    mvClips,
    300,
    "Asaf",
    "MV_KM_FRAC",
    true
  );
  assertNoOverrun(plan, mvClips);
  const sorted = [...plan.items].sort((a, b) => a.atSec - b.atSec);
  const firstOutroIdx = sorted.findIndex((i) => i.role === "outro");
  const lastIntroIdx = sorted.map((i) => i.role).lastIndexOf("intro");
  const lastInstrIdx = sorted.map((i) => i.role).lastIndexOf("instruction");
  assert.ok(firstOutroIdx >= 0, "has outro");
  assert.ok(lastIntroIdx >= 0, "has intro");
  assert.ok(lastInstrIdx >= 0, "has instruction");
  assert.ok(lastIntroIdx < firstOutroIdx, "intros before outro");
  assert.ok(lastInstrIdx < firstOutroIdx, "instructions before outro");
});

test("MV_KM_FRAC 60s: no reminders when under REMINDER_THRESHOLD", () => {
  const plan = composeMorningVisualizationPlan(
    mvClips,
    60,
    "Asaf",
    "MV_KM_FRAC",
    true
  );
  assertNoOverrun(plan, mvClips);
  const n = plan.items.filter((i) => i.role === "reminder").length;
  assert.equal(n, 0);
});

test("MV_GR_FRAC 300s can schedule gratitude-only reminder MVG_C010", () => {
  const plan = composeMorningVisualizationPlan(
    mvClips,
    300,
    "Asaf",
    "MV_GR_FRAC",
    true
  );
  assertNoOverrun(plan, mvClips);
  const ids = plan.items.map((i) => i.clipId);
  assert.ok(
    ids.includes("MVG_C010"),
    "expected MVG_C010 (gratitude reminder) in long GR session"
  );
});

test("MV_KM_FRAC never includes MVG_C010", () => {
  const plan = composeMorningVisualizationPlan(
    mvClips,
    300,
    "Asaf",
    "MV_KM_FRAC",
    true
  );
  const ids = plan.items.map((i) => i.clipId);
  assert.ok(!ids.includes("MVG_C010"));
  assert.ok(!ids.some((id) => id.startsWith("MVG_")));
});

test("MV_GR_FRAC never includes MVK_ clips", () => {
  const plan = composeMorningVisualizationPlan(
    mvClips,
    300,
    "Asaf",
    "MV_GR_FRAC",
    true
  );
  const ids = plan.items.map((i) => i.clipId);
  assert.ok(!ids.some((id) => id.startsWith("MVK_")));
});

test("MV outro chain: five outro clips in ascending order field", () => {
  const plan = composeMorningVisualizationPlan(
    mvClips,
    300,
    "Asaf",
    "MV_KM_FRAC",
    true
  );
  const byId = new Map(mvClips.map((c) => [c.clipId, c]));
  const outros = plan.items
    .filter((i) => i.role === "outro")
    .sort((a, b) => a.atSec - b.atSec);
  assert.equal(outros.length, 5);
  const orders = outros.map((i) => byId.get(i.clipId)?.order ?? 0);
  for (let i = 1; i < orders.length; i++) {
    assert.ok(orders[i] > orders[i - 1], "outros follow catalog order");
  }
});
