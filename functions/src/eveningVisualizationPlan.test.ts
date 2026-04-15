/**
 * Evening Visualization: deterministic ordering, prefix isolation, no overrun.
 */
import assert from "node:assert/strict";
import * as fs from "fs";
import * as path from "path";
import { test } from "node:test";
import type { FractionalClip } from "./fractionalComposer";
import {
  composeEveningVisualizationPlan,
  isEveningVisualizationModuleId,
} from "./eveningVisualizationPlan";
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

const evClips = loadCatalog("evening_visualization_fractional.json");

test("isEveningVisualizationModuleId", () => {
  assert.equal(isEveningVisualizationModuleId("EV_KM_FRAC"), true);
  assert.equal(isEveningVisualizationModuleId("EV_GR_FRAC"), true);
  assert.equal(isEveningVisualizationModuleId("MV_KM_FRAC"), false);
});

test("EV_KM_FRAC 900s: only EVK clipIds, instructions before reminders before outros", () => {
  const plan = composeEveningVisualizationPlan(evClips, 900, "Asaf", "EV_KM_FRAC", true);
  assert.ok(plan.items.length > 0);
  for (const it of plan.items) {
    assert.ok(it.clipId.startsWith("EVK_"), `unexpected clip ${it.clipId}`);
  }
  const roles = plan.items.map((i) => {
    const c = evClips.find((x) => x.clipId === i.clipId);
    return c?.role;
  });
  const firstOut = roles.findIndex((r) => r === "outro");
  const lastInstr = roles.lastIndexOf("instruction");
  const lastRem = roles.lastIndexOf("reminder");
  assert.ok(firstOut > lastInstr, "outro after instructions");
  if (lastRem >= 0) assert.ok(firstOut > lastRem, "outro after reminders");
  assertNoOverrun(plan, evClips);
});

test("EV_GR_FRAC 900s: only EVG clipIds", () => {
  const plan = composeEveningVisualizationPlan(evClips, 900, "Asaf", "EV_GR_FRAC", false);
  assert.ok(plan.items.length > 0);
  for (const it of plan.items) {
    assert.ok(it.clipId.startsWith("EVG_"), `unexpected clip ${it.clipId}`);
  }
  assertNoOverrun(plan, evClips);
});

test("EV_KM_FRAC never includes EVG clips", () => {
  const plan = composeEveningVisualizationPlan(evClips, 600, "Asaf", "EV_KM_FRAC", false);
  assert.ok(!plan.items.some((i) => i.clipId.startsWith("EVG_")));
});

test("EV_GR_FRAC never includes EVK clips", () => {
  const plan = composeEveningVisualizationPlan(evClips, 600, "Asaf", "EV_GR_FRAC", false);
  assert.ok(!plan.items.some((i) => i.clipId.startsWith("EVK_")));
});

test("EV_KM_FRAC 120s: plan fits without overrun", () => {
  const plan = composeEveningVisualizationPlan(evClips, 120, "Asaf", "EV_KM_FRAC", false);
  assertNoOverrun(plan, evClips);
});
