/** @see ../../docs/fractional-module-intro-rule.md */
process.env.GCLOUD_PROJECT = "imaginedev-e5fd3";

import assert from "node:assert/strict";
import { test } from "node:test";
import { expandFractionalCues } from "./fractionalComposer";
import { INTRO_FRAC_FIRST_SPEECH_OFFSET_SEC } from "./introFractionalPlan";

test("expandFractionalCues: long session — intro prefix then PB at practice minute 1 (60s + 60s)", () => {
  const out = expandFractionalCues(
    [
      {
        id: "INT_FRAC",
        name: "Intro",
        url: "",
        trigger: "start",
      },
      {
        id: "PB_FRAC",
        name: "PB",
        url: "",
        trigger: 1,
        durationMinutes: 2,
      },
    ],
    20,
    "Asaf"
  );
  // 20m practice → 60s intro cap; practice-relative minute 1 → absolute 60 + 60 = 120s.
  const pbAt120 = out.find(
    (c) => c.trigger === "s120" && String(c.id).startsWith("PBV_")
  );
  assert.ok(pbAt120, "expected a Perfect Breath clip at 120s (intro prefix + 1 practice min)");
});

test("expandFractionalCues: INT_FRAC first atomic cue at 7s", () => {
  const out = expandFractionalCues(
    [
      {
        id: "INT_FRAC",
        name: "Intro",
        url: "",
        trigger: "start",
        durationMinutes: 2,
      },
    ],
    10,
    "Asaf"
  );
  const first = out.find((c) => c.id.startsWith("INT_"));
  assert.ok(first);
  assert.equal(first!.trigger, `s${INTRO_FRAC_FIRST_SPEECH_OFFSET_SEC}`);
});

test("expandFractionalCues: second fractional row skips PB OPEN for 2m block (even if trigger is start)", () => {
  const out = expandFractionalCues(
    [
      {
        id: "IM_FRAC",
        name: "I AM",
        url: "",
        trigger: "start",
        durationMinutes: 2,
      },
      {
        id: "PB_FRAC",
        name: "PB",
        url: "",
        trigger: "start",
        durationMinutes: 2,
      },
    ],
    10,
    "Asaf"
  );
  assert.ok(
    !out.some((c) => c.id === "PBV_OPEN_000_INTRO_ASAF"),
    "PB block under 5m and not first fractional row must not emit OPEN"
  );
});

test("expandFractionalCues: non-fractional cue before IM_FRAC at start skips IM framing intro for 3m", () => {
  const out = expandFractionalCues(
    [
      {
        id: "VC",
        name: "Vision",
        url: "",
        trigger: "start",
      },
      {
        id: "IM_FRAC",
        name: "I AM",
        url: "",
        trigger: "start",
        durationMinutes: 3,
      },
    ],
    10,
    "Asaf"
  );
  assert.ok(
    !out.some((c) => c.id === "IM_C001"),
    "regular intro first → fractional module must not emit IM framing intro"
  );
});

test("expandFractionalCues: sole PB_FRAC row still gets OPEN for 2m when first fractional", () => {
  const out = expandFractionalCues(
    [
      {
        id: "PB_FRAC",
        name: "PB",
        url: "",
        trigger: "start",
        durationMinutes: 2,
      },
    ],
    10,
    "Asaf"
  );
  assert.ok(
    out.some((c) => c.id === "PBV_OPEN_000_INTRO_ASAF"),
    "single PB row is first fractional — OPEN allowed for >60s window"
  );
  const open = out.find((c) => c.id === "PBV_OPEN_000_INTRO_ASAF");
  assert.ok(open);
  assert.equal(
    open!.trigger,
    `s${INTRO_FRAC_FIRST_SPEECH_OFFSET_SEC}`,
    "first PB voice at global first-speech offset when first fractional"
  );
});
