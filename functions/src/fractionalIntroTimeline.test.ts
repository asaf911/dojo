/** @see ../../docs/fractional-module-intro-rule.md */
import assert from "node:assert/strict";
import { test } from "node:test";
import type { FractionalClip } from "./fractionalComposer";
import { composeFractionalPlan } from "./fractionalComposer";

const intro: FractionalClip = {
  clipId: "NF_INTRO",
  role: "intro",
  order: 1,
  text: "We will now begin a focus exercise.",
  voices: { Asaf: "gs://x/a.mp3" },
};

const p0: FractionalClip = {
  clipId: "NF_P0",
  role: "instruction",
  order: 2,
  priority: "p0",
  text: "Core line",
  voices: { Asaf: "gs://x/b.mp3" },
};

test("composeFractionalPlan skips framing intro under 5 min when not at timeline start", () => {
  const plan = composeFractionalPlan([intro, p0], 180, "Asaf", "NF_FRAC", false);
  assert.ok(!plan.items.some((i) => i.role === "intro"));
});

test("composeFractionalPlan includes framing intro under 5 min when at timeline start", () => {
  const plan = composeFractionalPlan([intro, p0], 180, "Asaf", "NF_FRAC", true);
  assert.ok(plan.items.some((i) => i.role === "intro"));
  assert.equal(plan.items[0]?.clipId, "NF_INTRO");
});
