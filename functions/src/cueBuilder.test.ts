import assert from "node:assert/strict";
import { test } from "node:test";
import { buildCuesFromAllocation } from "./cueBuilder";

test("buildCuesFromAllocation: NF focus emits monolithic NF5 when focus minutes is 5", () => {
  const cues = buildCuesFromAllocation(
    {
      intro: 0,
      breath: 1,
      relax: 2,
      focus: 5,
      insight: 0,
      focusType: "NF",
    },
    {
      noBreathwork: false,
      isSleep: false,
      isMorning: false,
      isEvening: false,
    },
    { bodyScanDirection: "down" }
  );
  const nf = cues.find((c) => c.id.startsWith("NF") && /^NF\d+$/.test(c.id));
  assert.equal(nf?.id, "NF5");
});

test("buildCuesFromAllocation: NF focus clamps to NF10 when focus > 10", () => {
  const cues = buildCuesFromAllocation(
    {
      intro: 0,
      breath: 0,
      relax: 0,
      focus: 15,
      insight: 0,
      focusType: "NF",
    },
    {
      noBreathwork: false,
      isSleep: false,
      isMorning: false,
      isEvening: false,
    },
    {}
  );
  const nf = cues.find((c) => /^NF\d+$/.test(c.id));
  assert.equal(nf?.id, "NF10");
});

test("buildCuesFromAllocation (dev project): NF focus emits NF_FRAC", () => {
  const prev = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = "imaginedev-e5fd3";
  try {
    const cues = buildCuesFromAllocation(
      {
        intro: 0,
        breath: 1,
        relax: 2,
        focus: 5,
        insight: 0,
        focusType: "NF",
      },
      {
        noBreathwork: false,
        isSleep: false,
        isMorning: false,
        isEvening: false,
      },
      { bodyScanDirection: "down" }
    );
    assert.ok(cues.some((c) => c.id === "NF_FRAC"));
  } finally {
    if (prev === undefined) {
      delete process.env.GCLOUD_PROJECT;
    } else {
      process.env.GCLOUD_PROJECT = prev;
    }
  }
});
